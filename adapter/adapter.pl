use DynaLoader;
my $lib = DynaLoader::dl_load_file($ARGV[0], 0x01) or die DynaLoader::dl_error();
my $sym = DynaLoader::dl_find_symbol($lib, "adapter_run") or die "sem adapter_run";
DynaLoader::dl_install_xsub("main::adapter_run", $sym);
adapter_run();
