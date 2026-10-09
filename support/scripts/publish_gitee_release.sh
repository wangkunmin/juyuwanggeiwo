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
  while read -r old; do
    [ -n "$old" ] || continue
    code_del="$(curl -s --max-time 60 -o /dev/null -w '%{http_code}' \
      -X DELETE "$API/releases/$RID/attach_files/$old?access_token=$GITEE_TOKEN")"
    echo "  删除同名旧附件 ${name}（id=$old）-> HTTP ${code_del}"
  done <<< "$(get_asset_ids "$name")"
  code="$(curl -s --max-time 900 -o /tmp/gitee_upload.json -w '%{http_code}' \
    -X POST "$API/releases/$RID/attach_files" \
    -F "access_token=$GITEE_TOKEN" -F "file=@$f")"
  if [ "$code" = "201" ] || [ "$code" = "200" ]; then
    echo "  ✓ 已上传 ${name}（HTTP ${code}，$(du -h "$f" | cut -f1)）"
  else
    echo "  ✗ 上传失败 ${name}（HTTP ${code}）"
    head -c 300 /tmp/gitee_upload.json 2>/dev/null; echo
    failed=1
  fi
done

exit "$failed"
