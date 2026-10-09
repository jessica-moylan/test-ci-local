This is written in attempt to duplicate [this GitHub](https://github.com/NSLS2/gha-beamline-integration-test) locally in response to not having an easy way to debug after a failed run.

To run: `scripts/base.sh <tla> <profile collection> <branch>` ex: `scripts/base.sh hex hex-profile-collection main`

Docker is required

Working Profiles as of Oct 9
A few beamlines had to be run using the pixi branches since they were not merged into main (for these profiles, the main (or master) branch is unable to be tested)

Progress on beamlines:
- [ ] chx - pulls repos from local (https://github.com/NSLS2/chx-profile-collection/blob/b2555d5cdabb3be5e725a0d28438a9ca202ce02c/startup/01-chxsetup.py#L25)
- [ ] cms 
- [x] csx
- [x] fmx - uses pixi_2026C2 branch
- [x] fxi 
- [x] hex - kafka errors (but non blocking)
- [ ] hxn - need to fix pathing
- [x] ios
- [x] isr
- [ ] iss - pulls git repos locally (https://github.com/NSLS2/iss-profile-collection/blob/b2c6b292c51ec4983d041165aff6b6ce641bd13a/pixi.toml#L51)
- [x] ixs
- [ ] lix - posible redis DNS issue with docker
- [x] nyx
- [ ] opls - need to refix where ipython and where things are located in
- [ ] pdf - AttributeError: 'CatalogOfBlueskyRuns' object has no attribute 'insert'
- [ ] qas - pulls git repos locally (https://github.com/NSLS2/qas-profile-collection/blob/c72294ff5d1e3726debfe4d97ede355a922de39e/pixi.toml#L39)
- [x] six 
- [ ] sml ??? unclear 
- [x] srx
- [ ] tes - pixi_2026C2 needs to be pushed to master
- [ ] tst
- [x] xfm - pixi_2026C3 needs to be pushed to master
- [ ] xfm-maia - missing `qmicroscope` dependency from pixi in pixi_2026C3
- [ ] xfp - need to refix where ipython and where things are located in
- [ ] xpd 
- [ ] xpdd - need a consistant way tfor access
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