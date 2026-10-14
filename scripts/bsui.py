import io, os, glob, sys, traceback, warnings
import re
import ophyd
from ophyd import Device
import ophyd.device
import ophyd.signal
from ophyd.signal import _unset_value_sentinel

# EPICS MOCKING ---------------------------------------------------------------------
PLUGIN_TYPE_PVS = [
    (re.compile(r'image\d:'), 'NDPluginStdArrays'),
    (re.compile(r'Stats\d:'), 'NDPluginStats'),
    (re.compile(r'CC\d:'), 'NDPluginColorConvert'),
    (re.compile(r'Proc\d:'), 'NDPluginProcess'),
    (re.compile(r'Over\d:'), 'NDPluginOverlay'),
    (re.compile(r'ROI\d:'), 'NDPluginROI'),
    (re.compile(r'Trans\d:'), 'NDPluginTransform'),
    (re.compile(r'netCDF\d:'), 'NDFileNetCDF'),
    (re.compile(r'TIFF\d:'), 'NDFileTIFF'),
    (re.compile(r'JPEG\d:'), 'NDFileJPEG'),
    (re.compile(r'Nexus\d:'), 'NDPluginNexus'),
    (re.compile(r'HDF\d:'), 'NDFileHDF5'),
    (re.compile(r'Magick\d:'), 'NDFileMagick'),
    (re.compile(r'Current\d:'), 'NDPluginStats'),
    (re.compile(r'SumAll'), 'NDPluginStats'),
]

def fabricate_default_value(pvname):
    """Generates realistic default values based on PV patterns."""
    pvname_str = str(pvname or '')
    if 'PluginType' in pvname_str:
        for pattern, val in PLUGIN_TYPE_PVS:
            if pattern.search(pvname_str):
                return val
        return 'NDPluginStats'
    elif 'ArrayPort' in pvname_str or 'PortName' in pvname_str:
        return pvname_str
    elif 'EnableCallbacks' in pvname_str or 'BlockingCallbacks' in pvname_str or 'Auto' in pvname_str or 'WaitForPlugins' in pvname_str:
        return 1
    elif 'ImageMode' in pvname_str or 'WriteMode' in pvname_str:
        return 'Single'
    elif 'ArraySize' in pvname_str:
        return 10
    elif 'FilePathExists' in pvname_str:
        return 1
    elif 'file' in pvname_str.lower() and 'number' not in pvname_str.lower() and 'mode' not in pvname_str.lower():
        return '/tmp/mock_file'
    elif 'filenumber' in pvname_str.lower():
        return 0
    elif pvname_str.endswith(".EGU"):
        return "mm"
    elif pvname_str.endswith(".STAT") or pvname_str.endswith(".SEVR"):
        return "NO_ALARM"
    elif pvname_str.endswith(".ACKT") or pvname_str.endswith(".ACKS"):
        return "YES"
    return 0.0
    
class MockEpicsSignal(ophyd.Signal):
    """Mock Signal replacing EpicsSignal and EpicsSignalRO."""
    _default_kwargs = {}

    @classmethod
    def set_defaults(cls, **kwargs):
        cls._default_kwargs.update(kwargs)

    def __init__(self, read_pv=None, write_pv=None, *args, **kwargs):
        if read_pv is None and len(args) > 0:
            read_pv = args[0]
        pvname = read_pv or write_pv or kwargs.get('pvname', 'MOCK_PV')
        clean_name = kwargs.pop('name', None) or str(pvname).replace(':', '_').replace('.', '_')

        merged_kwargs = dict(type(self)._default_kwargs)
        merged_kwargs.update(kwargs)
        kwargs = merged_kwargs

        epics_keys = [
            'string', 'auto_monitor', 'put_complete', 'limits', 
            'use_suffix', 'omit_from_described', 'metadata',
            'timeout', 'connection_timeout', 'datatype', 'rtstr'
        ]
        for key in epics_keys:
            kwargs.pop(key, None)

        if 'value' not in kwargs:
            kwargs['value'] = fabricate_default_value(pvname)

        super().__init__(name=clean_name, **kwargs)

        self._metadata_dict = {}
        self.pvname = pvname
        self.read_pv = read_pv
        self.write_pv = write_pv or read_pv
        
    @property
    def connected(self):
        return True
    
    @property
    def metadata(self):
        base_meta = getattr(super(), 'metadata', {})
        return {**base_meta, **self._metadata_dict} if isinstance(base_meta, dict) else self._metadata_dict

    @metadata.setter
    def metadata(self, val):
        if isinstance(val, dict):
            self._metadata_dict.update(val)
        else:
            self._metadata_dict['custom'] = val

    def wait_for_connection(self, timeout=None):
        return True

    def _ensure_connected(self, *args, **kwargs):
        return True

    def check_value(self, value):
        pass

    def _get_with_timeout(self, *args, **kwargs):
        return {
            "value": self.get() if hasattr(self, '_readback') else 0.0,
            "status": 0,
            "severity": 0,
            "timestamp": 0.0,
        }

    def get(self, *args, **kwargs):
        val = getattr(self, "_readback", _unset_value_sentinel)
        if val is _unset_value_sentinel or val is None:
            val = fabricate_default_value(getattr(self, "pvname", ""))
            self._readback = val
        return val

    def put(self, value, *args, **kwargs):
        self._readback = value
        return value

class MockEpicsSignalWithRBV(MockEpicsSignal):
    """Mock Signal replacing EpicsSignalWithRBV."""
    def __init__(self, prefix=None, *args, **kwargs):
        if prefix is None and len(args) > 0:
            prefix = args[0]
        read_pv = f"{prefix}_RBV" if prefix else "MOCK_RBV"
        write_pv = prefix or "MOCK_PV"
        super().__init__(read_pv=read_pv, write_pv=write_pv, **kwargs)

class MockEpicsMotor(ophyd.EpicsMotor):
    """Mock Motor retaining standard EpicsMotor component structure without EPICS connection."""
    def __init__(self, prefix=None, *args, **kwargs):
        if prefix is None and len(args) > 0:
            prefix = args[0]
        clean_name = kwargs.pop('name', None) or str(prefix or 'mock_motor').replace(':', '_').replace('{', '_').replace('}', '_')
        super().__init__(prefix=prefix or "MOCK:MOTOR", name=clean_name, **kwargs)

    def wait_for_connection(self, timeout=None):
        return True

    def _ensure_connected(self, *args, **kwargs):
        return True

    @property
    def position(self):
        return getattr(self, '_readback', 1.0)
    
    def __getattr__(self, name):
        if name not in self.__dict__ and not name.startswith('_'):
            sig = MockEpicsSignal(name=f"{self.name}_{name}")
            setattr(self, name, sig)
            return sig
        raise AttributeError(f"'{type(self).__name__}' object has no attribute '{name}'")

class MockEpicsDevice(Device):
    """Mock Device."""
    def wait_for_connection(self, timeout=None):
            print(f"MockEpicsDevice.wait_for_connection called for device: {getattr(self, 'name', 'unknown')}")
            return True

    def __getattr__(self, name):
        if name.startswith("_"):
            raise AttributeError(name)
        if name not in self._signals:
            sig = MockEpicsSignal(
                read_pv=f"{getattr(self, 'prefix', '')}{name}",
                name=f"{self.name}_{name}",
            )
            self._signals[name] = sig
        return self._signals[name]

def mock_get_with_timeout(self, pv=None, *args, **kwargs):
    pvname = getattr(pv, 'pvname', getattr(self, 'pvname', ''))
    val = fabricate_default_value(pvname)
    
    return {
        "value": val,
        "status": 0,
        "severity": 0,
        "timestamp": 0.0,
    }

def _ci_signal_get(self, *args, **kwargs):
    val = getattr(self, "_readback", _unset_value_sentinel)
    if isinstance(val, _unset_value_sentinel) or val is None:
        pvname = getattr(self, "pvname", getattr(self, "name", ""))
        val = fabricate_default_value(pvname)
        self._readback = val

    return val

def _ci_wait_for_connection(self, timeout=None):
    return True

def _ci_ensure_connected(self, *args, **kwargs):
    return True

ophyd.EpicsSignal = MockEpicsSignal
ophyd.EpicsSignalRO = MockEpicsSignal
ophyd.EpicsSignalWithRBV = MockEpicsSignalWithRBV
ophyd.EpicsMotor = MockEpicsMotor
ophyd.Device = MockEpicsDevice

ophyd.signal.EpicsSignal = MockEpicsSignal
ophyd.signal.EpicsSignalRO = MockEpicsSignal
ophyd.signal.EpicsSignalWithRBV = MockEpicsSignalWithRBV
ophyd.device.Device = MockEpicsDevice

ophyd.Device.wait_for_connection = _ci_wait_for_connection
ophyd.device.Device.wait_for_connection = _ci_wait_for_connection
ophyd.signal.Signal.wait_for_connection = _ci_wait_for_connection
ophyd.signal.Signal.get = MockEpicsSignal.get
# ophyd.signal.EpicsSignalBase.wait_for_connection = _ci_wait_for_connection
# ophyd.signal.EpicsSignalBase._ensure_connected = _ci_ensure_connected

if hasattr(ophyd.signal, 'EpicsSignalBase'):
    ophyd.signal.EpicsSignalBase.wait_for_connection = _ci_wait_for_connection
    ophyd.signal.EpicsSignalBase._ensure_connected = _ci_ensure_connected
    ophyd.signal.EpicsSignalBase._get_with_timeout = mock_get_with_timeout

if hasattr(ophyd, 'areadetector') and hasattr(ophyd.areadetector, 'base'):
    ophyd.areadetector.base.ADBase.wait_for_connection = _ci_wait_for_connection
    ophyd.areadetector.base.ADBase._ensure_connected = _ci_ensure_connected


# Get system arguments, needed currently for SIX with user inputs
# TODO: do both SIX endatations, six and keithley, need to be tested?
beamline_acronym = os.environ.get('BEAMLINE_ACRONYM', 'unknown')
six_endstation1 = 'six'

ip = get_ipython()
profile_collection_dir = os.getcwd()

if ip is not None and hasattr(ip, 'profile_dir'):
    ip.profile_dir.startup_dir = profile_collection_dir

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
    import datetime
    import xpdacq
    import xpdacq.xpdacq_conf

    def _ci_load_beamline_config(beamline_config_fp, verif='', test=True):
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

def text_replace(file_path, old_text, new_text):
    with open(file_path, 'r') as file:
        content = file.read()

    content = content.replace(old_text, new_text)

    with open(file_path, 'w') as file:
        file.write(content)


startup_files = sorted(glob.glob(os.path.join(os.getcwd(), 'startup/*.py')))
print(f'Found startup files: {os.getcwd()}/startup/*.py -> \n{startup_files}')

if os.path.isfile('.ci/drop-in.py'):
    startup_files.append('.ci/drop-in.py')

if beamline_acronym == 'lix':
    os.environ['BS_CONFIG'] = 'proc'

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
            text_replace(f, 'RUNNING_IN_NSLS2_CI = False', 'RUNNING_IN_NSLS2_CI = True')
            ip.parent._exec_file(f)

        elif f.endswith('00-startup.py') and beamline_acronym == 'hxn':
            text_replace(f, '= _epicssignal_get', '= _ci_signal_get')
            ip.parent._exec_file(f)

        elif f.endswith('94-load.py') and beamline_acronym == 'pdf':
            text_replace(f, 'glbl[\'blconfig_path\']', 'glbl[\'blconfig_path\'], test = True')
            ip.parent._exec_file(f)

        else:
            ip.parent._exec_file(f)

    except Exception as e:
        print(f'ERROR in {f}:')
        traceback.print_exc()
        raise