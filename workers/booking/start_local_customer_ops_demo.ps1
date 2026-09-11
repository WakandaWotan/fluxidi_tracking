# Local Klantenbeheer / import / offerte demo. No production KV or real mail.
# Worker persist: .\workers\booking\.local-customer-ops-demo\
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
Write-Host "Worker: http://127.0.0.1:8788"
Write-Host "Mail sink: http://127.0.0.1:8788/local/customer-quote-mail"
Write-Host "Sample CSV: http://127.0.0.1:8788/local/contacts_demo.csv"
node local_customer_ops_demo.mjs
