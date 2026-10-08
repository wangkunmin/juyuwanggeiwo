# UNCOMMENT THESE LINES TO BUILD FROM LATEST COMMIT
# git reset --hard origin/main
# git pull

param(
    [Parameter(Mandatory=$true)]
    [string]$CERTIFICATE_PASSWORD,

    # 证书路径：默认放在 ../secrets/ 下并用自己的文件名；
    # 也可用参数或环境变量 CERTIFICATE_PATH 覆盖（不要沿用上游作者的证书文件名）
    [string]$CERTIFICATE_PATH = $(if ($env:CERTIFICATE_PATH) { $env:CERTIFICATE_PATH } else { "../secrets/juyuwanggeiwo-windows.pfx" })
)

cd app
fvm flutter clean
fvm flutter pub get
fvm dart run msix:create --certificate-path $CERTIFICATE_PATH --certificate-password $CERTIFICATE_PASSWORD

Move-Item -Path build/windows/x64/runner/Release/localsend_app.msix -Destination juyuwanggeiwo-XXX-windows-x86-64.msix

cd ..

Write-Output 'Generated Signed Windows msix!'
