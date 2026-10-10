#!/usr/bin/env bash
#
# 把构建产物发布到 Gitee Release（幂等：同名附件会先被删除再上传）。
#
# 用法：
#   GITEE_TOKEN=xxx GITEE_REPO=ynzj/juyuwanggeiwo RELEASE_TAG=v1.18.2-resume.1 \
#     bash support/scripts/publish_gitee_release.sh *.dmg *.sha256
#
# 说明：
#   - 未设置 GITEE_TOKEN 时直接跳过（返回 0），这样本地/未配置密钥的流水线不受影响；
#   - 单个文件上传失败不会中断其它文件，最后以非 0 退出码汇总报告。
#
set -uo pipefail

REPO="${GITEE_REPO:-ynzj/juyuwanggeiwo}"
TAG="${RELEASE_TAG:-v1.18.2-resume.1}"

if [ -z "${GITEE_TOKEN:-}" ]; then
  echo "未设置 GITEE_TOKEN，跳过 Gitee 发布"
  exit 0
fi

API="https://gitee.com/api/v5/repos/$REPO"

get_release_id() {
  curl -s --max-time 30 "$API/releases/tags/$TAG" \
    | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    print(d.get("id", "") if isinstance(d, dict) else "")
except Exception:
    print("")'
}

get_asset_ids() {
  # 返回该 Release 下所有同名附件的 id（Gitee 的 release JSON 不含 id，
  # 必须走专门的 attach_files 列表接口；同名附件可能有多份，全部返回）
  local want="$1"
  curl -s --max-time 30 "$API/releases/$RID/attach_files?access_token=$GITEE_TOKEN" \
    | WANT="$want" python3 -c 'import json,os,sys
want = os.environ["WANT"]
try:
    items = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if not isinstance(items, list):
    sys.exit(0)
for a in items:
    if a.get("name") == want:
        print(a.get("id", ""))'
}

RID="$(get_release_id)"
if [ -z "$RID" ]; then
  echo "找不到 Release（tag=${TAG}），跳过发布"
  exit 0
fi
echo "目标 Release：$REPO tag=$TAG id=$RID"

failed=0
for f in "$@"; do
  [ -e "$f" ] || continue
  name="$(basename "$f")"

  # 关键：**先上传成功，再清理同名旧附件**。
  # 早期实现是"先删后传"，一旦上传失败（CI 里真实发生过：45MB 的 arm64 包没传上去），
  # 已发布的同名资产就被删掉了，用户会直接丢包。Gitee 允许多个同名附件，
  # 因此这里先传、成功后再删旧副本。
  code="$(curl -s --retry 3 --retry-all-errors --max-time 1800 -o /tmp/gitee_upload.json -w '%{http_code}' \
    -X POST "$API/releases/$RID/attach_files" \
    -F "access_token=$GITEE_TOKEN" -F "file=@$f")"

  if [ "$code" != "201" ] && [ "$code" != "200" ]; then
    echo "  ✗ 上传失败 ${name}（HTTP ${code}）—— 保留原有附件，不做删除"
    head -c 300 /tmp/gitee_upload.json 2>/dev/null; echo
    failed=1
    continue
  fi
  echo "  ✓ 已上传 ${name}（HTTP ${code}，$(du -h "$f" | cut -f1)）"

  # 上传成功后，清理同名旧副本（保留刚上传的那个）
  newest="$(curl -s --max-time 60 "$API/releases/$RID/attach_files?access_token=$GITEE_TOKEN" \
    | WANT="$name" python3 -c 'import json,os,sys
want = os.environ["WANT"]
try:
    items = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ids = [a.get("id") for a in items if isinstance(a, dict) and a.get("name") == want]
print(max(ids) if ids else "")')"
  if [ -n "$newest" ]; then
    curl -s --max-time 60 "$API/releases/$RID/attach_files?access_token=$GITEE_TOKEN" \
      | WANT="$name" KEEP="$newest" python3 -c 'import json,os,sys
want, keep = os.environ["WANT"], int(os.environ["KEEP"])
items = json.load(sys.stdin)
for a in items:
    if a.get("name") == want and a.get("id") != keep:
        print(a.get("id"))' \
      | while read -r old; do
          curl -s --max-time 60 -o /dev/null \
            -X DELETE "$API/releases/$RID/attach_files/$old?access_token=$GITEE_TOKEN"
          echo "    已删除同名旧副本 id=$old"
        done
  fi
done

exit "$failed"
