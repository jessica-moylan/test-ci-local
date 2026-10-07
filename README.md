This is written in attempt to duplicate [this GitHub](https://github.com/NSLS2/gha-beamline-integration-test) locally in response to not having an easy way to debug after a failed run.

To run: `scripts/base.sh <tla> <profile collection> <branch>` ex: `scripts/base.sh hex hex-profile-collection main`

Docker is required

Working Profiles as of Oct 7
A few beamlines had to be run using my branches due to needed updates/modernizing (noted by bold)

Progress on beamlines:
- [ ] chx - pulls repos from local (https://github.com/NSLS2/chx-profile-collection/blob/b2555d5cdabb3be5e725a0d28438a9ca202ce02c/startup/01-chxsetup.py#L25)
- [ ] cms 
- [x] csx
- [x] fmx - uses pixi_2026C2 branch
- [x] fxi 
- [x] hex - kafka errors (but non blocking)
- [ ] hxn - need to fix pathing
- [x] ios
- [x] **isr: needed LICENSE**
- [ ] iss - pulls git repos locally (https://github.com/NSLS2/iss-profile-collection/blob/b2c6b292c51ec4983d041165aff6b6ce641bd13a/pixi.toml#L51)
- [x] **ixs: needed LICENSE**
- [ ] lix
- [x] nyx
- [x] opls
- [ ] pdf - AttributeError: 'CatalogOfBlueskyRuns' object has no attribute 'insert'
- [ ] qas - pulls git repos locally (https://github.com/NSLS2/qas-profile-collection/blob/c72294ff5d1e3726debfe4d97ede355a922de39e/pixi.toml#L39)
- [x] six 
- [ ] sml ??? unclear 
- [x] srx
- [ ] tes - pixi_2026C2 needs to be pushed to master
- [ ] tst
- [ ] xfm - pixi_2026C2 needs to be pushed to master, as well as adding a LICENSE file and missing `scikit-beam` dependency
- [ ] xfm-maia
- [ ] xfp
- [ ] xpd 
- [ ] xpdd
************** COMPLETED AT A LATER DATE ***************
- [ ] amx
- [ ] cdi
************** OTHER ********************************************
- [ ] bmm (already has a testing suite)
************** NOT CURRENTLY PLANNED *******************
- [ ] arpes
- [ ] xpeem
- [ ] haxpes
- [ ] nexafs
- [ ] rsoxs
- [ ] vppem