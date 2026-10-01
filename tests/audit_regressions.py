#!/usr/bin/env python3
"""Real helper/process regression tests. All files and processes are test-owned."""
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


def js(code):
    return json.loads(subprocess.check_output(["node", "-e", code], cwd=ROOT, text=True))


LIB = js("""
const fs=require('fs'),vm=require('vm');
const S=require('./Settings.js'), R=require('./Roots.js');
const source=fs.readFileSync('ai/AiBackend.js','utf8');
const start=source.indexOf('var OUTPUT_GUARD_PROGRAM =');
let c={};vm.createContext(c);vm.runInContext(source.slice(start,source.indexOf('// argv behind',start)),c);
console.log(JSON.stringify({reader:S.FILE_READER_PROGRAM,writer:S.FILE_WRITER_PROGRAM,
  metadata:R.INDEX_META_PROGRAM,guard:c.OUTPUT_GUARD_PROGRAM}));
""")


def helper(name, *args):
    return ["perl", "-e", LIB[name], "--", *map(str, args)]


def run(argv):
    return subprocess.run(argv, capture_output=True, text=True, timeout=8)


class SettingsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="omni-settings-")
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.path = self.directory / "state.json"

    def write(self, ops, limit=65536):
        return run(helper("writer", self.directory, self.path, limit, json.dumps(ops)))

    def test_missing_and_refused_reads_differ(self):
        self.assertEqual(run(helper("reader", self.path, 100)).returncode, 2)
        self.path.write_text("x" * 101)
        self.assertEqual(run(helper("reader", self.path, 100)).returncode, 1)
        self.path.unlink()
        os.mkfifo(self.path)
        self.assertEqual(run(helper("reader", self.path, 100)).returncode, 1)

    def test_patch_preserves_unknown_and_nested_keys(self):
        self.path.write_text('{"custom":42,"models":{"pi":"a","codex":"b"}}')
        r = self.write([{"path": ["models", "pi"], "value": "c"}])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(self.path.read_text()), {"custom": 42, "models": {"pi": "c", "codex": "b"}})
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)
        r = self.write([{"path": ["models", "pi"], "remove": True}])
        self.assertEqual(json.loads(r.stdout)["models"], {"codex": "b"})

    def test_concurrent_writers_and_defaults(self):
        self.path.write_text('{"appsView":"grid","custom":42}')
        processes = []
        for i in range(8):
            ops = [{"path": ["models", str(i)], "value": i},
                   {"path": ["appsView"], "value": "list", "missingOnly": True}]
            processes.append(subprocess.Popen(helper("writer", self.directory, self.path, 65536, json.dumps(ops)), stdout=subprocess.PIPE, stderr=subprocess.PIPE))
        for p in processes:
            _, err = p.communicate(timeout=8)
            self.assertEqual(p.returncode, 0, err)
        self.assertEqual(json.loads(self.path.read_text()), {"appsView": "grid", "custom": 42, "models": {str(i): i for i in range(8)}})

    def test_invalid_or_large_files_are_unchanged(self):
        for original in ["", "{", "[]", "null", "1", '{"large":"' + "a" * 200 + '"}']:
            with self.subTest(original=original):
                self.path.write_text(original)
                r = self.write([{"path": ["appsView"], "value": "grid"}], 100)
                self.assertNotEqual(r.returncode, 0)
                self.assertEqual(self.path.read_text(), original)

    def test_symlinks_and_bad_lock_are_refused(self):
        target = self.directory / "target"
        target.write_text('{"keep":true}')
        self.path.symlink_to(target)
        self.assertEqual(run(helper("reader", self.path, 100)).returncode, 1)
        self.assertNotEqual(self.write([]).returncode, 0)
        self.assertTrue(self.path.is_symlink())
        self.assertEqual(target.read_text(), '{"keep":true}')
        self.path.unlink()
        lock = Path(str(self.path) + ".lock")
        lock.unlink()
        lock.symlink_to(target)
        self.assertNotEqual(self.write([]).returncode, 0)
        self.assertEqual(target.read_text(), '{"keep":true}')

    def test_write_failure_is_not_success(self):
        # The destination cannot be replaced, and failure must reach the UI.
        self.path.mkdir()
        self.assertNotEqual(self.write([{"path": ["x"], "value": 1}]).returncode, 0)
        self.assertEqual(list(self.directory.glob(".settings.*")), [])

    def test_symlinked_and_group_writable_directories_still_save(self):
        real = self.directory / "real"
        real.mkdir()
        link = self.directory / "link"
        link.symlink_to(real)
        path = link / "state.json"
        r = run(helper("writer", link, path, 65536, json.dumps([{"path": ["a"], "value": 1}])))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads((real / "state.json").read_text()), {"a": 1})
        real.chmod(0o775)
        r = run(helper("writer", real, real / "state.json", 65536, json.dumps([{"path": ["b"], "value": 2}])))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads((real / "state.json").read_text()), {"a": 1, "b": 2})
        self.assertEqual(real.stat().st_mode & 0o022, 0)

    def test_remove_on_missing_parent_creates_nothing(self):
        self.path.write_text('{"keep":1}')
        r = self.write([{"path": ["p", "q"], "remove": True}])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(self.path.read_text()), {"keep": 1})

    def test_stale_temp_files_are_removed(self):
        old = self.directory / ".settings.AbCd1234"
        fresh = self.directory / ".settings.ZyXw9876"
        other = self.directory / ".settings.notmatching"
        for f in (old, fresh, other):
            f.write_text("x")
        os.utime(old, (time.time() - 600,) * 2)
        os.utime(other, (time.time() - 600,) * 2)
        r = self.write([{"path": ["a"], "value": 1}])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(old.exists())
        self.assertTrue(fresh.exists())
        self.assertTrue(other.exists())

    def test_read_contract_and_store_do_not_reset_on_failure(self):
        result = js(r"""
const fs=require('fs'),vm=require('vm'),Settings=require('./Settings.js');
const src=fs.readFileSync('SettingsStore.qml','utf8');
const fn=src.match(/^  function applyState\([^]*?^  }/m)[0];
let saves=0;
const store={stateData:{keep:42},menu:{},stateWritable:true,error:''};
const c={store,Settings,stateWriteProc:{save(){saves++}}};vm.createContext(c);vm.runInContext(fn,c);
const cases=[[1,0],[124,0],[0,1]];
for(const [code,status] of cases)c.applyState('',code,status);
console.log(JSON.stringify({state:store.stateData,saves,writable:store.stateWritable,
  missing:Settings.readObject('',2,0), empty:Settings.readObject('',0,0)}));
""")
        self.assertEqual(result["state"], {"keep": 42})
        self.assertEqual(result["saves"], 0)
        self.assertFalse(result["writable"])
        self.assertTrue(result["missing"]["missing"])
        self.assertFalse(result["empty"]["ok"])


class ModelTests(unittest.TestCase):
    def test_jsonc_strings_and_comments(self):
        result = js(r'''
const M=require('./MenuModel.js');
const value={label:'a,} b,]',action:'printf "x,}"; # /*literal*/ // literal',url:'https://a/b',quoted:'"\\'};
const original=JSON.stringify(value);
const withComments='/*start*/'+original.slice(0,-1)+', // trailing\n}';
console.log(JSON.stringify([JSON.parse(M.stripJsonc(original)),JSON.parse(M.stripJsonc(withComments))]));
''')
        self.assertEqual(result[0], result[1])
        self.assertEqual(result[0]["label"], "a,} b,]")
        self.assertIn('x,}', result[0]["action"])

    def test_mtime_expiry_pruning_and_closed_menu(self):
        result = js(r'''
const fs=require('fs'),vm=require('vm');
const src=fs.readFileSync('FileSearchController.qml','utf8');
const fn=name=>src.match(new RegExp('^  function '+name+'\\([^]*?^  }','m'))[0];
const searcher={menu:{opened:true,rebuildDisplay(){}},fileResults:[{path:'/a'},{path:'/b'}],
 fileMtimes:{'/a':1,'/gone':2},fileMtimeReadAt:{'/a':90000,'/gone':90000},mtimeTtlMs:30000,fileSearchGen:2,fileResultsVersion:0};
const statProc={running:false};
const c={searcher,statProc,Date:{now:()=>100000}};vm.createContext(c);
vm.runInContext(fn('fetchFileMtimes')+'\n'+fn('applyFileMtimes'),c);
c.fetchFileMtimes(); const first=statProc.paths;
statProc.running=false;searcher.fileMtimeReadAt['/a']=1;c.fetchFileMtimes();const expired=statProc.paths;
c.applyFileMtimes({'/a':99},['/a','/b']);
statProc.running=false;searcher.menu.opened=false;c.fetchFileMtimes();
console.log(JSON.stringify({first,expired,cache:searcher.fileMtimes,readAt:searcher.fileMtimeReadAt,closedStarted:statProc.running}));
''')
        self.assertEqual(result["first"], ["/b"])
        self.assertEqual(result["expired"], ["/a", "/b"])
        self.assertEqual(result["cache"], {"/a": 99})
        self.assertEqual(result["readAt"], {"/a": 100000, "/b": 100000})
        self.assertFalse(result["closedStarted"])


class IndexTests(unittest.TestCase):
    def test_metadata_reuse_and_index_replacement(self):
        with tempfile.TemporaryDirectory(prefix="omni-meta-") as d:
            path = Path(d) / "root.idx"
            path.write_bytes(b"/a\0/b\0unfinished")
            command = helper("metadata", path, 65536, 0)
            self.assertEqual(run(command).stdout, "2")
            meta = Path(str(path) + ".meta")
            signature = meta.read_text().split("\t")[0]
            # A matching sidecar is actually used; the index is not recounted.
            meta.write_text(signature + "\t123\n")
            self.assertEqual(run(command).stdout, "123")
            replacement = Path(d) / "new.idx"
            replacement.write_bytes(b"/c\0")
            replacement.replace(path)
            self.assertEqual(run(command).stdout, "1")
            self.assertNotEqual(meta.read_text().split("\t")[0], signature)
            self.assertNotEqual(run(helper("metadata", path, 1, 0)).returncode, 0)


def stopped(pid):
    try:
        return Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[0] == "Z"
    except FileNotFoundError:
        return True


class SupervisorTests(unittest.TestCase):
    def scenario(self, kind):
        code = """
import os,signal,time
signal.signal(signal.SIGTERM,signal.SIG_IGN)
child=os.fork()
if child==0:
    time.sleep(6)
    os._exit(0)
print(str(os.getpid())+' '+str(child),flush=True)
"""
        code += {"cancel": "time.sleep(6)", "timeout": "time.sleep(6)",
                 "overflow": "print('x'*5000,flush=True);time.sleep(6)",
                 "normal": "os._exit(0)"}[kind]
        argv = helper("guard", 10000, 1024, 1000, 4096, "--", "python3", "-u", "-c", code)
        if kind == "timeout":
            argv = ["timeout", "-k", "2", "1", *argv]
        p = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
        owned = []
        try:
            self.assertTrue(select.select([p.stdout], [], [], 3)[0], "test child did not start")
            owned = list(map(int, p.stdout.readline().split()))
            self.assertEqual(len(owned), 2)
            if kind == "cancel":
                p.send_signal(signal.SIGTERM)
            p.communicate(timeout=4)
            self.assertEqual(p.returncode, {"normal": 0, "cancel": 143, "overflow": 143, "timeout": 124}[kind])
            self.assertTrue(all(stopped(pid) for pid in owned), f"surviving children: {owned}")
        finally:
            if p.poll() is None:
                p.kill()
            p.communicate(timeout=3)
            for pid in owned:
                if not stopped(pid):
                    os.kill(pid, signal.SIGKILL)

    def test_cancel(self):
        self.scenario("cancel")

    def test_timeout(self):
        self.scenario("timeout")

    def test_output_limit(self):
        self.scenario("overflow")

    def test_exit_while_consumer_is_slow_loses_nothing(self):
        # SIGCHLD lands while the guard is blocked writing to a slow consumer.
        script = "head -c 148000 /dev/zero | tr '\\0' a | fold -w 80"
        expected = len(run(["sh", "-c", script]).stdout)
        for _ in range(8):
            p = subprocess.Popen(helper("guard", 10000, 1 << 24, 1000, 4096, "--", "sh", "-c", script),
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
            time.sleep(1)
            out, _err = p.communicate(timeout=10)
            self.assertEqual(len(out), expected)
            self.assertEqual(p.returncode, 0)

    def test_normal_exit_cleans_inherited_pipes(self):
        self.scenario("normal")


if __name__ == "__main__":
    unittest.main()
