import io, os, glob, sys, traceback, warnings

# Get system arguments, needed currently for SIX with user inputs
# TODO: do both SIX endatations, six and keithley, need to be tested?
beamline_acronym = os.environ.get('BEAMLINE_ACRONYM', 'unknown')
six_endstation1 = 'six'

ip = get_ipython()

# Test for CI  for fixxing startup files do not fail when authentication.links is None.
try:
    from tiled.client.context import Context

    def _ci_fixed_whoami(self):
        auth = getattr(self.server_info, 'authentication', None)
        links = getattr(auth, 'links', None)
        if links:
            return self.http_client.get(
                links.whoami,
                headers={'Accept': 'application/x-msgpack'},
            ).json()
        else:
            warnings.warn('Authentication providers were not configured on the server.')

    Context.whoami = _ci_fixed_whoami
    print('Applied CI monkey patch for tiled Context.whoami')
except Exception as exc:
    print(f'Could not apply Tiled monkey patch: {exc}')      
    
# Monkey Patch the xpdAcq _load_beamline_config since 1.0.0 does not have the pass for CI
try:
    import platform
    import subprocess
    import yaml
    import os
    import xpdacq
    from xpdacq.xpdacq_conf import _load_beamline_config

    def _ci_load_beamline_config(beamline_config_fp, verif='', test=False):
        if (not test) and (not os.path.isfile(beamline_config_fp)):
            raise xpdacq.tools.xpdAcqException(
                'WARNING: can not find long term beamline '
                'configuration file. Please contact the '
                'beamline scientist ASAP'
            )
        os_type = platform.system()
        if os_type == 'Windows':
            editor = 'notepad'
        else:
            editor = os.environ.get('EDITOR', 'vim')
        beamline_config = dict()
        if not test:
            while verif.upper() not in ('Y', 'YES'):
                with open(beamline_config_fp, 'r') as f:
                    beamline_config = yaml.unsafe_load(f)
                verif = input('\nIs this configuration correct? y/n: ')
                if verif.upper() in ('N', 'NO'):
                    print('Edit, save, and close the configuration file.\n')
                    subprocess.call([editor, beamline_config_fp])
            beamline_config['Verified by'] = input('Please input your initials: ')
            timestamp = datetime.datetime.now()
            beamline_config['Verification time'] = timestamp.strftime(
                '%Y-%m-%d %H:%M:%S'
            )
            with open(beamline_config_fp, 'w') as f:
                yaml.dump(beamline_config, f)
        return beamline_config

    xpdacq.xpdacq_conf._load_beamline_config = _ci_load_beamline_config
    print('Applied CI monkey patch for xpdacq.xpdacq_conf._load_beamline_config')
except Exception as exc:
    print(f'Could not apply xpdacq.xpdacq_conf monkey patch: {exc}')

startup_files = sorted(glob.glob(os.path.join(os.getcwd(), 'startup/*.py')))
print(f'Found startup files: {os.getcwd()}/startup/*.py -> {startup_files}')
if os.path.isfile('.ci/drop-in.py'):
    startup_files.append('.ci/drop-in.py')
if not startup_files:
    raise SystemExit(f'Cannot find any startup files in {os.getcwd()}')

for f in startup_files:
    if not os.path.isfile(f):
        raise FileNotFoundError(f'File {f} cannot be found.')
    print(f'Executing {f} in CI')
    try:
        if f.endswith('00-startup.py') and beamline_acronym == 'six':
            sys.argv = ['00-startup.py', 'arg1']

            simulated_inputs = 'SIX\n'
            sys.stdin = io.StringIO(simulated_inputs)

            ip.parent._exec_file(f)

            sys.stdin = sys.__stdin__
            sys.argv = [sys.argv[0]]
        elif f.endswith('01-prompt.py') and beamline_acronym == 'opls':
            RE.md['proposal_number'] = '123456'
            RE.md['main_proposer'] = 'test_user'
            
        # TODO: Is there a cleaner way to do this without having to modify the file? Perhaps using other types of overrides
        elif f.endswith('00-startup.py') and beamline_acronym == 'hex':
            with open(f, 'r') as file:
                content = file.read()
            
            content = content.replace('RUNNING_IN_NSLS2_CI = False', 'RUNNING_IN_NSLS2_CI = True')
            
            with open(f, 'w') as file:
                file.write(content)

            ip.parent._exec_file(f)
        else:
            ip.parent._exec_file(f)
    except Exception as e:
        print(f'ERROR in {f}:')
        traceback.print_exc()
        raise