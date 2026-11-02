#!/usr/bin/env python3
"""FloatTabs Phase 7 Real-Mac acceptance harness.

Current product semantics are Automatic / Keep Loaded only. The Debug control
endpoint still accepts the legacy residency wire value; this harness uses it
only as a compatibility transport and verifies canonical `runtime_retention`
before judging results. It never clears Browser Profile/session/site data.
"""

from __future__ import annotations

import argparse, csv, json, sys, time
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Set

import floattabs_benchmark as core

AUTO = "automatic"
KEEP = "keepLoaded"
PAUSE = "pauseWhenInactive"
GRACE = 30.0
DEFAULT_INTERVAL = 2.0
DEFAULT_TIMEOUT = 45.0
WIRE = {AUTO: "warm", KEEP: "hot"}


class AcceptanceError(RuntimeError):
    pass


def profiles(status):
    return {str(p["id"]): dict(p) for p in core.control_profiles(status) if p.get("id")}


def retention(profile):
    value = profile.get("runtime_retention")
    if value not in {AUTO, KEEP}:
        raise AcceptanceError("Phase 7 canonical runtime_retention is unavailable.")
    return str(value)


def configure(client, ids, preference, media=PAUSE):
    status = client.configure(ids, WIRE[preference], media)
    by_id = profiles(status)
    for slot_id in ids:
        p = by_id.get(slot_id)
        if not p or p.get("runtime_retention") != preference or p.get("background_media") != media:
            raise AcceptanceError(f"Canonical policy verification failed for {slot_id}.")
    return status


def resident_ids(status) -> Set[str]:
    return {str(x) for x in (status.get("resident_slot_ids") or [])}


def ask(prompt, default=False):
    suffix = " [Y/n] " if default else " [y/N] "
    while True:
        value = input(prompt + suffix).strip().lower()
        if not value:
            return default
        if value in {"y", "yes"}: return True
        if value in {"n", "no"}: return False


def choose(status, explicit):
    items = core.control_profiles(status)
    if explicit:
        if len(explicit) != 3 or len(set(explicit)) != 3:
            raise AcceptanceError("Pass exactly three distinct --slot-id values.")
        by_id = profiles(status)
        if any(slot_id not in by_id for slot_id in explicit):
            raise AcceptanceError("Unknown --slot-id.")
        return [by_id[x] for x in explicit]
    if len(items) < 3:
        raise AcceptanceError("At least three configured ChatGPT Slots are required.")
    print("\nSelect three real ChatGPT Slots as A/B/C:")
    for i, p in enumerate(items, 1):
        print(f"  {i:>2}. {str(p.get('name','Unnamed'))[:36]:<36} "
              f"retention={p.get('runtime_retention','?')} media={p.get('background_media','?')}")
    raw = input("Indexes (example 1,2,3): ").strip()
    try:
        indexes = [int(x.strip()) for x in raw.split(",") if x.strip()]
    except ValueError as exc:
        raise AcceptanceError("Indexes must be numeric.") from exc
    if len(indexes) != 3 or len(set(indexes)) != 3 or any(i < 1 or i > len(items) for i in indexes):
        raise AcceptanceError("Select exactly three valid distinct indexes.")
    return [dict(items[i - 1]) for i in indexes]


def extract_generating(value) -> Optional[bool]:
    if isinstance(value, dict):
        for key, child in value.items():
            k = str(key).replace("-", "_").lower()
            if k in {"generating", "is_generating", "generation_active"} and isinstance(child, (bool, int)):
                return bool(child)
            found = extract_generating(child)
            if found is not None: return found
    elif isinstance(value, list):
        for child in value:
            found = extract_generating(child)
            if found is not None: return found
    return None


class Recorder:
    def __init__(self, session, host_pid, resolver, client, selected, interval):
        self.session, self.host_pid, self.resolver, self.client = session, host_pid, resolver, client
        self.selected, self.interval = tuple(selected), interval
        self.started = time.monotonic()
        self.rows, self.events = [], []

    def event(self, kind, scenario, detail, **extra):
        item = {"captured_at": core.iso_now(), "elapsed_s": round(time.monotonic()-self.started,3),
                "kind": kind, "scenario": scenario, "detail": detail, **extra}
        self.events.append(item)
        print(f"  EVENT {item['elapsed_s']:>7.1f}s {scenario}: {detail}", flush=True)
        (self.session/"lifecycle-events.json").write_text(json.dumps(self.events,indent=2,ensure_ascii=False))

    def sample(self, scenario):
        self.resolver.refresh(force=not self.rows)
        owned = self.resolver.snapshot()
        metrics = core.ps_metrics([self.host_pid, *owned.keys()])
        if self.host_pid not in metrics:
            raise AcceptanceError("FloatTabs exited during acceptance.")
        process = core.aggregate_sample(self.host_pid, owned, metrics, time.monotonic()-self.started)
        status = self.client.status()
        residents = resident_ids(status)
        selected = sorted(residents.intersection(self.selected))
        webcontent = sorted(pid for pid, meta in owned.items() if meta.get("kind") == "webcontent")
        row = {
            "captured_at": core.iso_now(), "elapsed_s": round(time.monotonic()-self.started,3),
            "scenario": scenario, "panel_visible": bool(status.get("visible",False)),
            "active_slot_id": status.get("active_slot_id") or "",
            "resident_slot_count": int(status.get("resident_slot_count",len(residents)) or 0),
            "selected_resident_count": len(selected), "selected_resident_ids": ";".join(selected),
            "pending_automatic_plan_count": int(status.get("pending_warm_release_count",0) or 0),
            "legacy_cold_pending_count": int(status.get("pending_cold_release_count",0) or 0),
            "media_protected_count": len(status.get("media_protected_slot_ids") or []),
            "webcontent_pids": ";".join(map(str,webcontent)),
            **{k:v for k,v in process.items() if k != "elapsed_s"},
        }
        self.rows.append(row); self.flush_csv()
        return row

    def observe(self, scenario, seconds):
        end=time.monotonic()+seconds; rows=[]
        while time.monotonic() < end or not rows:
            row=self.sample(scenario); rows.append(row)
            print(f"  {row['elapsed_s']:7.1f}s resident={row['resident_slot_count']} "
                  f"selected={row['selected_resident_count']}/3 WC={row.get('webcontent_count',0)} "
                  f"RSS={core.human_mb(float(row.get('total_rss_kb',0)))}", flush=True)
            time.sleep(self.interval)
        return rows

    def flush_csv(self):
        if not self.rows: return
        with (self.session/"lifecycle-timeline.csv").open("w",newline="",encoding="utf-8") as f:
            w=csv.DictWriter(f,fieldnames=list(self.rows[0].keys())); w.writeheader(); w.writerows(self.rows)


def activate(client, rec, slot_id, scenario, timeout=20.0):
    client.activate(slot_id); end=time.monotonic()+timeout
    while time.monotonic() < end:
        status=client.status()
        if status.get("active_slot_id")==slot_id and slot_id in resident_ids(status):
            rec.event("activation",scenario,f"activated {slot_id}",slot_id=slot_id); return status
        rec.sample(scenario); time.sleep(0.25)
    raise AcceptanceError(f"Slot {slot_id} did not materialize within {timeout}s.")


def pidset(row):
    out=set()
    for x in str(row.get("webcontent_pids") or "").split(";"):
        try:
            if x: out.add(int(x))
        except ValueError: pass
    return out


def automatic_scenario(client, rec, ids, interval, timeout):
    a,b,c=ids; name="automatic_convergence"
    rec.event("scenario_start",name,"A/B/C Automatic; load A→B→C")
    configure(client,ids,AUTO); client.show()
    for slot in ids:
        activate(client,rec,slot,name); time.sleep(1)
    before=rec.sample(name); before_pids=pidset(before)

    budget_deadline=time.monotonic()+12
    budget=False
    while time.monotonic()<budget_deadline:
        st=client.status()
        if resident_ids(st).intersection(ids)=={b,c} and st.get("active_slot_id")==c:
            budget=True; break
        rec.sample(name); time.sleep(0.5)

    rows=rec.observe(name,timeout)
    final=client.status(); tracked=resident_ids(final).intersection(ids)
    converged=tracked=={c} and final.get("active_slot_id")==c
    after=rows[-1]; removed=sorted(pidset(before)-pidset(after))
    memory=bool(removed) or int(after.get("webcontent_count",0)) < int(before.get("webcontent_count",0))
    result={"status":"PASS" if budget and converged else "FAIL",
            "normal_budget_lru":"PASS" if budget else "FAIL",
            "after_grace_only_active":"PASS" if converged else "FAIL",
            "final_selected_residents":sorted(tracked),
            "aggregate_webcontent_pid_disappearances":removed,
            "memory_directional_support":"PASS" if memory else "NOT_PROVEN",
            "memory_note":"Aggregate FloatTabs/WebKit evidence only; no exact per-Slot PID attribution."}
    rec.event("scenario_end",name,result["status"],**result); return result


def rapid_scenario(client, rec, ids):
    a,b,_=ids; name="rapid_a_b_a"; client.show()
    rec.event("scenario_start",name,"rapid A→B→A")
    client.activate(a); time.sleep(.35); client.activate(b); time.sleep(.35); client.activate(a); time.sleep(2)
    st=client.status(); machine=st.get("active_slot_id")==a and a in resident_ids(st); rec.sample(name)
    human=ask("Rapid A→B→A 后是否稳定显示 A，且没有持续错页/错误 Slot 挂接？")
    result={"status":"PASS" if machine and human else "FAIL",
            "machine_final_active":"PASS" if machine else "FAIL",
            "human_visible_slot":"PASS" if human else "FAIL"}
    rec.event("scenario_end",name,result["status"],**result); return result


def generation_scenario(client, rec, ids, interval, timeout):
    _,b,c=ids; name="background_generation"; configure(client,[b,c],AUTO)
    activate(client,rec,b,name); client.show()
    print("\n在 B 中启动一个足够长的 ChatGPT 回复；确认仍在生成后按 Enter。"); input()
    seen=None
    try: seen=extract_generating(client.chatgpt_measurement_snapshot(b))
    except Exception: pass
    client.activate(c); deadline=time.monotonic()+timeout; ended=False
    while time.monotonic()<deadline:
        rec.sample(name); current=None
        try: current=extract_generating(client.chatgpt_measurement_snapshot(b))
        except Exception: pass
        if current is True: seen=True
        if seen is True and current is False: ended=True; break
        if b not in resident_ids(client.status()):
            result={"status":"INCOMPLETE" if ended else "FAIL",
                    "resident_past_grace":"NOT_PROVEN" if ended else "FAIL",
                    "generating_observed_by_probe":seen,"post_completion_reclaim":"NOT_RUN"}
            rec.event("scenario_end",name,result["status"],**result); return result
        time.sleep(interval)
    if ended:
        result={"status":"INCOMPLETE","resident_past_grace":"NOT_PROVEN",
                "generating_observed_by_probe":seen,"post_completion_reclaim":"NOT_RUN",
                "reason":"Generation ended before full grace window."}
        rec.event("scenario_end",name,"INCOMPLETE",**result); return result

    print("\nB 已跨过 grace 且仍 resident。等生成完成后按 Enter。"); input()
    if not ask("确认 B 已停止生成？",True):
        result={"status":"INCOMPLETE","resident_past_grace":"PASS",
                "generating_observed_by_probe":seen,"post_completion_reclaim":"NOT_PROVEN"}
        rec.event("scenario_end",name,"INCOMPLETE",**result); return result
    deadline=time.monotonic()+timeout; reclaimed=False
    while time.monotonic()<deadline:
        rec.sample(name)
        if b not in resident_ids(client.status()): reclaimed=True; break
        time.sleep(interval)
    result={"status":"PASS" if reclaimed else "FAIL","resident_past_grace":"PASS",
            "generating_observed_by_probe":seen,
            "post_completion_reclaim":"PASS" if reclaimed else "FAIL"}
    rec.event("scenario_end",name,result["status"],**result); return result


def keep_scenario(client, rec, ids, timeout):
    a,_,c=ids; name="keep_loaded_ordinary"; configure(client,[a],KEEP); configure(client,[c],AUTO)
    activate(client,rec,a,name); activate(client,rec,c,name); rec.observe(name,timeout)
    st=client.status(); r=resident_ids(st); ok=a in r and c in r and st.get("active_slot_id")==c
    result={"status":"PASS" if ok else "FAIL","keep_loaded_after_grace":"PASS" if a in r else "FAIL",
            "relaunch_non_preload":"PENDING_SEPARATE_CHECK"}
    rec.event("scenario_end",name,result["status"],**result); return result


def restore_scenario(client, rec, ids, interval, timeout):
    a,_,c=ids; name="restore_session_continuity"; configure(client,[a,c],AUTO)
    activate(client,rec,a,name); activate(client,rec,c,name)
    deadline=time.monotonic()+timeout; reclaimed=False
    while time.monotonic()<deadline:
        rec.sample(name)
        if a not in resident_ids(client.status()): reclaimed=True; break
        time.sleep(interval)
    if not reclaimed:
        result={"status":"FAIL","runtime_reclaimed":"FAIL","runtime_restored":"NOT_RUN",
                "human_session_continuity":"NOT_RUN"}
        rec.event("scenario_end",name,"FAIL",**result); return result
    activate(client,rec,a,name); restored=a in resident_ids(client.status())
    print("\nA 已 reclaim→restore。只检查仍登录、Browser Profile 正确、会话/页面可继续；不要 reset/reload。")
    human=ask("Session continuity 是否正常？")
    result={"status":"PASS" if restored and human else "FAIL","runtime_reclaimed":"PASS",
            "runtime_restored":"PASS" if restored else "FAIL",
            "human_session_continuity":"PASS" if human else "FAIL"}
    rec.event("scenario_end",name,result["status"],**result); return result


def overall(scenarios, relaunch):
    states=[str(v.get("status")) for v in scenarios.values()]
    if "FAIL" in states: return "FAIL"
    if any(x in {"INCOMPLETE","NOT_RUN","NOT_PROVEN"} for x in states): return "INCOMPLETE"
    return "PASS" if relaunch=="PASS" else "PENDING_RELAUNCH"


def write_outputs(session, rec, scenarios, relaunch, warnings):
    result={"generated_at":core.iso_now(),"overall":overall(scenarios,relaunch),
            "scenarios":scenarios,"keep_loaded_relaunch":relaunch,
            "warning_critical_pressure":{"status":"PROVEN_BY_MACHINE_TESTS",
                "note":"Current Debug control has no safe pressure injection; Phase 7 contract permits deterministic test proof."},
            "warnings":list(warnings)}
    text=json.dumps(result,indent=2,ensure_ascii=False)
    (session/"acceptance-result.json").write_text(text); (session/"lifecycle-summary.json").write_text(text)
    lines=["# FloatTabs Phase 7 Real-Mac Acceptance","",f"Overall: **{result['overall']}**","",
           "| Scenario | Result |","| --- | --- |"]
    for name,value in scenarios.items(): lines.append(f"| `{name}` | **{value.get('status','UNKNOWN')}** |")
    lines += [f"| `keep_loaded_relaunch` | **{relaunch}** |",
              "| `warning_critical_pressure` | **PROVEN_BY_MACHINE_TESTS** |","",
              "## Evidence boundary","",
              "- Runtime resident IDs come from the Debug control channel.",
              "- WebKit PID/RSS is aggregate directional evidence only; no exact per-Slot attribution is claimed.",
              "- Login/Cookie/session continuity is user-observed; page content is not collected.",
              "- Hot/Warm/Cold are not acceptance semantics; old wire values are compatibility transport only."]
    (session/"lifecycle-report.md").write_text("\n".join(lines))
    rows_json=json.dumps(rec.rows,ensure_ascii=False)
    (session/"lifecycle-chart.html").write_text(
        "<!doctype html><meta charset=utf-8><title>Phase 7 timeline</title>"
        "<h1>FloatTabs Phase 7 timeline</h1><p>Raw samples (aggregate process evidence only).</p>"
        f"<script>const rows={rows_json};</script><pre id=o></pre>"
        "<script>o.textContent=rows.map(r=>`${r.elapsed_s}s  ${r.scenario}  resident=${r.resident_slot_count} "
        "selected=${r.selected_resident_count} RSS_MB=${((Number(r.total_rss_kb)||0)/1024).toFixed(1)}`).join('\\n')</script>"
    )
    return result


def restore(client, manifest):
    for p in manifest.get("original_profiles") or []:
        client.configure([str(p["id"])],WIRE[str(p["runtime_retention"])],str(p.get("background_media") or PAUSE))
    active=manifest.get("original_active_slot_id")
    if isinstance(active,str) and active: client.activate(active)
    client.show() if manifest.get("original_visible") else client.hide()


def run(args):
    core.ensure_macos(); host,warnings=core.choose_host_pid(args.pid)
    if not args.no_sudo: core.validate_sudo()
    resolver=core.OwnershipResolver(host); resolver.refresh(force=True); client=core.BenchmarkControlClient(host)
    initial=client.status()
    if str(initial.get("fullscreen_source_state") or "idle")!="idle":
        raise AcceptanceError("Exit fullscreen before acceptance.")
    chosen=choose(initial,args.slot_id); ids=[str(p["id"]) for p in chosen]
    if not ask("确认 A/B/C 都是 ChatGPT Slot，当前无生成中回复，可用于无保护 baseline？"):
        raise AcceptanceError("Unprotected baseline not confirmed.")
    by_id=profiles(initial)
    originals=[{"id":i,"name":by_id[i].get("name"),"runtime_retention":retention(by_id[i]),
                "background_media":by_id[i].get("background_media") or PAUSE} for i in ids]
    git_sha=core.git_value(["rev-parse","HEAD"]); dirty=core.git_value(["status","--porcelain"],default="")
    if dirty.strip() and not args.allow_dirty: raise AcceptanceError("Checkout is dirty; final evidence requires a clean exact head.")
    session=(core.DEFAULT_RESULTS_ROOT/(args.session or f"phase7-real-mac-{core.now_stamp()}")).resolve()
    if session.exists() and any(session.iterdir()): raise AcceptanceError(f"Session exists: {session}")
    session.mkdir(parents=True,exist_ok=True)
    manifest={"schema":1,"created_at":core.iso_now(),"kind":"phase7-real-mac-acceptance","git_sha":git_sha,
              "git_branch":core.git_value(["branch","--show-current"]),"host_pid":host,"system":core.system_info(),
              "selected_slots":[{"role":r,"id":i,"name":p.get("name")} for r,i,p in zip("ABC",ids,chosen)],
              "original_profiles":originals,"original_active_slot_id":initial.get("active_slot_id"),
              "original_visible":bool(initial.get("visible",False)),
              "policy":{"automatic_grace_seconds":GRACE,"normal_target":2,"warning_target":1,"critical_target":0},
              "pressure_injection":"not_available_in_current_debug_control","warnings":warnings}
    (session/"session.json").write_text(json.dumps(manifest,indent=2,ensure_ascii=False))
    rec=Recorder(session,host,resolver,client,ids,args.interval); scenarios={}
    try:
        scenarios["automatic_convergence"]=automatic_scenario(client,rec,ids,args.interval,args.timeout)
        scenarios["rapid_a_b_a"]=rapid_scenario(client,rec,ids)
        scenarios["background_generation"]=({"status":"NOT_RUN","reason":"--skip-generation"}
            if args.skip_generation else generation_scenario(client,rec,ids,args.interval,args.timeout))
        scenarios["keep_loaded_ordinary"]=keep_scenario(client,rec,ids,args.timeout)
        scenarios["restore_session_continuity"]=restore_scenario(client,rec,ids,args.interval,args.timeout)
    except Exception as exc:
        scenarios["harness_error"]={"status":"FAIL","error":str(exc)}; warnings.append(str(exc))
        rec.event("harness_error","harness",str(exc))
    finally:
        try: restore(client,manifest)
        except Exception as exc: warnings.append(f"restore failed: {exc}")
    result=write_outputs(session,rec,scenarios,"PENDING",warnings)
    print(f"\nMain run: {result['overall']}\nEvidence: {session}")
    print("Next: prepare-relaunch → normal quit/relaunch same Debug build → verify-relaunch.")
    return 0 if result["overall"] in {"PASS","PENDING_RELAUNCH"} else 1


def session_dir(value):
    p=Path(value).expanduser()
    return (p if p.is_absolute() else core.DEFAULT_RESULTS_ROOT/p).resolve()


def load_manifest(path):
    return json.loads((path/"session.json").read_text())


def prepare_relaunch(args):
    core.ensure_macos(); s=session_dir(args.session); m=load_manifest(s)
    selected=m["selected_slots"]; a=str(selected[0]["id"]); c=str(selected[2]["id"])
    host,_=core.choose_host_pid(args.pid); client=core.BenchmarkControlClient(host)
    configure(client,[a],KEEP); configure(client,[c],AUTO); client.show(); client.activate(a); time.sleep(2); client.activate(c); time.sleep(2)
    st=client.status()
    if a not in resident_ids(st) or st.get("active_slot_id")!=c: raise AcceptanceError("Could not prepare relaunch precondition.")
    (s/"relaunch-check.json").write_text(json.dumps({"status":"PREPARED","prepared_at":core.iso_now(),
        "keep_loaded_slot_id":a,"control_active_slot_id":c,"prepared_host_pid":host},indent=2))
    print(f"Prepared. Quit normally, relaunch same Debug build, do NOT select A, then run:\n"
          f"python3 tools/benchmark/floattabs_phase7_acceptance.py verify-relaunch --session {s}")
    return 0


def verify_relaunch(args):
    core.ensure_macos(); s=session_dir(args.session); m=load_manifest(s)
    rp=s/"relaunch-check.json"
    if not rp.exists(): raise AcceptanceError("Run prepare-relaunch first.")
    state=json.loads(rp.read_text()); a=str(state["keep_loaded_slot_id"])
    host,_=core.choose_host_pid(args.pid); client=core.BenchmarkControlClient(host); st=client.status(); by_id=profiles(st)
    if a not in by_id: raise AcceptanceError("Keep Loaded test Slot missing.")
    persisted=retention(by_id[a])==KEEP; absent=a not in resident_ids(st); result="PASS" if persisted and absent else "FAIL"
    state.update({"status":result,"verified_at":core.iso_now(),"verify_host_pid":host,
                  "preference_persisted":persisted,"not_proactively_materialized":absent,
                  "resident_slot_ids":sorted(resident_ids(st))}); rp.write_text(json.dumps(state,indent=2))
    restore(client,m)
    ap=s/"acceptance-result.json"; data=json.loads(ap.read_text()); data["keep_loaded_relaunch"]=result
    data["overall"]=overall(data.get("scenarios") or {},result); ap.write_text(json.dumps(data,indent=2,ensure_ascii=False))
    (s/"lifecycle-summary.json").write_text(json.dumps(data,indent=2,ensure_ascii=False))
    print(f"Keep Loaded relaunch: {result}; overall={data['overall']}"); return 0 if result=="PASS" else 1


def restore_cmd(args):
    core.ensure_macos(); s=session_dir(args.session); m=load_manifest(s)
    host,_=core.choose_host_pid(args.pid); restore(core.BenchmarkControlClient(host),m); print("Saved state restored."); return 0


def self_test():
    assert WIRE[AUTO]=="warm" and WIRE[KEEP]=="hot"
    assert extract_generating({"x":{"generating":True}}) is True
    assert extract_generating([{"is_generating":False}]) is False
    assert overall({"a":{"status":"PASS"}},"PENDING")=="PENDING_RELAUNCH"
    assert overall({"a":{"status":"PASS"}},"PASS")=="PASS"
    assert overall({"a":{"status":"FAIL"}},"PASS")=="FAIL"
    print("FloatTabs Phase 7 acceptance harness self-test: PASS"); return 0


def parser():
    p=argparse.ArgumentParser(description="FloatTabs Phase 7 Automatic/Keep Loaded Real-Mac acceptance.")
    p.add_argument("--self-test",action="store_true"); sub=p.add_subparsers(dest="command")
    r=sub.add_parser("run"); r.add_argument("--slot-id",action="append"); r.add_argument("--pid",type=int)
    r.add_argument("--session"); r.add_argument("--interval",type=float,default=DEFAULT_INTERVAL)
    r.add_argument("--timeout",type=float,default=DEFAULT_TIMEOUT); r.add_argument("--skip-generation",action="store_true")
    r.add_argument("--no-sudo",action="store_true"); r.add_argument("--allow-dirty",action="store_true")
    for name in ("prepare-relaunch","verify-relaunch","restore"):
        q=sub.add_parser(name); q.add_argument("--session",required=True); q.add_argument("--pid",type=int)
    return p


def main(argv:Optional[Sequence[str]]=None):
    p=parser(); a=p.parse_args(argv)
    if a.self_test: return self_test()
    if a.command=="run": return run(a)
    if a.command=="prepare-relaunch": return prepare_relaunch(a)
    if a.command=="verify-relaunch": return verify_relaunch(a)
    if a.command=="restore": return restore_cmd(a)
    p.print_help(); return 2


if __name__=="__main__":
    try: raise SystemExit(main())
    except (AcceptanceError,RuntimeError) as exc:
        print(f"ERROR: {exc}",file=sys.stderr); raise SystemExit(1)
