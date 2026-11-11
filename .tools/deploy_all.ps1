$products = @('_anniversary_', '_classic_', '_classic_beta_', '_classic_era_', '_classic_era_ptr_', '_forever_', '_retail_')
foreach ($p in $products) {
    & .tools/install_local.ps1 -Product $p
}
