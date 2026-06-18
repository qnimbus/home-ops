# Proposed Hardware Architecture — 5-Node Expansion

> **Status:** HARDWARE COMPLETE (updated 2026-06-13). All 5 nodes have drives and RAM installed.
> MS-A2 system disk migrated to Kingston NV3 1TB (AirDisk retired). All 5 nodes in maintenance
> mode — bootstrap in progress. All 4 Ceph OSD drives physically installed. This document reflects
> confirmed hardware state. It supersedes the abandoned Longhorn storage-VLAN effort
> (see [history/longhorn-storage-network.md](history/longhorn-storage-network.md)) — the storage tier is
> **Rook-Ceph** on the existing `10.200.0.0/24` bond fabric.
>
> ⚠️ **VERIFY** items from the original proposal — current status:
> - **MS-A2 slot count**: ✅ **CONFIRMED 3×** — all three slots now populated (T500 2TB + NV3 1TB + Phison E15T 256GB).
> - **M920q WLAN/2230 slot PCIe capability**: ✅ **CONFIRMED** — both M920q nodes enumerate 2 NVMe drives via AMT; since each M920q has only 1 native M.2 slot, the 2nd drive proves the WLAN slot carries PCIe/NVMe.
> - **M90q WLAN/2230 slot PCIe capability**: ✅ **CONFIRMED** — M90q #2 enumerates WD PC SN740 SDDQNQD-256G-1001 (a 2230-form-factor drive) as nvme0n1 in addition to the T500 2TB. Since M90q has only 2 native full-size slots and the WD SN740 is a 2230 drive, it must be in the WLAN/2230 slot — proving the slot carries PCIe/NVMe on M90q.

---

## Goal

A resilient Talos Linux + FluxCD + Rook-Ceph cluster with good storage performance, **sane failure
domains**, and efficient workload placement. The driving design priority chosen for this build is
**capacity-first Ceph** (maximise usable storage) while still retaining single-host self-heal.

---

## Nodes & Tiers

Five bare-metal nodes across three capability tiers. Strength order: **MS-A2 ≫ M90q (×2) > M920q (×2)**.

| Node | Tier | CPU | RAM | 10 GbE | Tier rationale |
|------|------|-----|-----|--------|----------------|
| **MS-A2** (Minisforum) | Premium | Ryzen 9 9955HX, 16C/32T | 96 GB **ECC** DDR5 (fixed) |  X710 dual SFP+ | Fastest CPU, ECC, most M.2 slots → control plane anchor + premium workloads + OSD |
| **M90q #1** (Lenovo) | Workhorse | i5-10500T, 6C/12T | 64 GB | X520 dual SFP+ | HT + 2 native M.2 slots → storage + general compute |
| **M90q #2** (Lenovo) | Workhorse | i5-10500T, 6C/12T | 64 GB *(drives installed; not yet provisioned)* | X520 dual SFP+ | As above |
| **M920q #1** (Lenovo) | Light | i5-8500T, 6C/6T | **32 GB** (2×16 GB SODIMMs) | X520 dual SFP+ | Oldest, no HT, single fast slot → OSD host (no etcd) |
| **M920q #2** (Lenovo) | Light | **i5-8600T**, 6C/6T | **64 GB** | X520 dual SFP+ | As above → control plane + light worker |

**RAM distribution (confirmed 2026-06-13):** the **6× 32 GB Kingston Fury Impact DDR4-3200**
SO-DIMMs (KF3200C20S4/32GX) are distributed across **M90q #1, M90q #2, and M920q #2 at 64 GB**
(2×32 each = all 6 modules). **M920q #1** runs 2×16 GB SODIMMs (32 GB total) — adequate for its
OSD + light worker role (no etcd). MS-A2's 96 GB ECC is fixed and never reassigned.

> The Fury modules are confirmed in M90q #1 and M920q #2 via Intel AMT. M90q #2 received the
> 2×32 GB modules that were initially shipped in M920q #1 — M920q #1 now runs 2×16 GB.

---

## M.2 Slot Budget (the binding constraint)

This architecture is shaped less by CPU/RAM than by **how many full-speed NVMe slots each chassis
exposes**. The slot inventory:

| Node | Full-speed slots (2280, x4) | Optional extra slot | OSD-grade homes |
|------|------------------------------|---------------------|-----------------|
| **MS-A2** | **3×** 2280 PCIe **4.0** x4 (slots 2/3 also take **22110** PLP) | — | 3 |
| **M90q #1 / #2** | **2×** 2280 PCIe **3.0** x4 *(native, bottom of mainboard)* | 3rd slot: repurposed M.2 PCIe **x1** WiFi module slot *(WLAN trick — unconfirmed PCIe on M90q, see note)* | 2 each *(3 with trick)* |
| **M920q #1 / #2** | **1×** 2280 PCIe x4 *(native, bottom of mainboard)* | 2nd slot: repurposed M.2 PCIe **x1** WiFi module slot *(✅ confirmed PCIe/NVMe — both M920q nodes run 2 NVMe drives)* | 1 each *(2 with trick)* |

Design rules derived from the slot budget:

1. **An OSD and a low-latency etcd disk both want a full-speed 2280.** A node with only one such slot
   (M920q) can host **either** an OSD **or** etcd — not both. Therefore **an OSD-hosting M920q must not
   run etcd** (its only fast slot is consumed; etcd would fall onto the slow boot slot — the fsync trap
   we avoid).
2. **MS-A2's three slots dissolve the OSD-vs-local-scratch trade-off** — it runs boot+etcd, an OSD,
   **and** a local NVMe scratch on three separate devices.
3. **A Talos boot disk does not need bandwidth** (read-mostly at startup, never on the etcd/Ceph hot
   path), so it is the right tenant for any slow/short slot. The M920q's WLAN slot is confirmed
   PCIe-capable on the live cluster (worker-01/worker-02 each enumerate two `nvmeXn1`), which is
   exactly how their boot SSDs are parked there.

> ✅ **CONFIRMED — MS-A2 slot count:** 3× M.2 confirmed — all three slots now populated (T500 2TB + Kingston NV3 1TB + Phison E15T 256GB).
>
> ✅ **CONFIRMED — M920q WLAN/2230 slots are PCIe/NVMe-capable:** both M920q #1 and M920q #2 enumerate 2 NVMe drives via Intel AMT. Since each M920q has only 1 native M.2 slot, the second drive in each node proves the WLAN slot carries PCIe and successfully hosts NVMe. Repurposing disables onboard Wi-Fi/BT (irrelevant for wired nodes).
>
> ✅ **CONFIRMED — M90q WLAN/2230 slot PCIe capability:** M90q #2 has a WD PC SN740 SDDQNQD-256G-1001 (2230 form factor) in its WLAN/M.2 PCIe x1 slot, enumerated as `nvme0n1` alongside the native-slot T500 2TB. The WLAN slot is confirmed PCIe/NVMe-capable on M90q — the growth path (extra OSD per M90q via WLAN slot) is viable.

---

## Final Node Roles & Disk Placement

| Node | K8s roles | etcd | Slot 1 (native, fast) | Slot 2 (native/WLAN) | Slot 3 (WLAN trick) |
|------|-----------|:----:|-----------------------|----------------------|---------------------|
| **MS-A2** | CP + OSD + **premium worker** | ✅ | **Crucial T500 2 TB** (CT2000T500SSD8) — OSD ✅ | **Kingston NV3 1 TB** (SNV3S1000G) — boot + etcd ✅ | **Phison E15T 256 GB** (YSR256GHLCA1-E5C-2) — local scratch ✅ |
| **M90q #1** | CP + OSD + worker | ✅ | **Crucial T500 2 TB** (CT2000T500SSD8) — OSD ✅ | **Kingston NV3 1 TB** (SNV3S1000G) — boot + etcd ✅ | *(vacant — now confirmed viable via M90q #2; see Growth Path)* |
| **M90q #2** | CP + OSD + worker | ✅ | **Crucial T500 2 TB** — OSD ✅ | **WD SN740 256 GB** (SDDQNQD-256G-1001) — boot ✅ *(WLAN slot, 2230 form factor)* | *(vacant — reserved OSD bay)* |
| **M920q #1** | OSD + light worker | — | **Crucial P310 2 TB** — OSD #4 ✅ *(installed 2026-06-13)* | **Goodram P44N 1 TB** — boot (WLAN slot) ✅ | — |
| **M920q #2** | CP + light worker | ✅ | **Kingston NV3 1 TB** (SNV3S1000G) — boot + etcd ✅ | **Crucial P310 1 TB** (CT1000P310SSD2) — spare/scratch ✅ | — |

**Control plane / etcd: MS-A2 + M90q #1 + M920q #2** (3 members — kept at 3, not 5, for etcd write
latency). Placement rationale:

- **One member per tier / hardware generation** — a thermal, PSU, or firmware fault affecting one
  chassis type cannot take quorum.
- **ECC-anchored on MS-A2** — an unprotected memory bit-flip in the etcd datastore is catastrophic
  corruption; the ECC node anchors quorum.
- **Never on M920q #1** — its single fast slot is the 4th OSD, so etcd has no fast home there.
- Colocation with OSDs/workloads on MS-A2 / M90q #1 is safe: Talos runs etcd as a **guaranteed-QoS
  static pod**, and every etcd member sits on a full-speed 2280 **separate** from any OSD device.

> etcd peer traffic stays on the management subnet (`advertisedSubnets: ["10.60.0.0/24"]`) — it never
> crosses the storage VLAN, consistent with current cluster policy.

---

## Rook-Ceph Topology

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| OSD hosts | **4** — MS-A2, M90q #1, M90q #2, M920q #1 | ≥4 hosts is the threshold for single-host **self-heal** under `size=3` |
| OSD devices | 3× **Crucial T500 2 TB** (DRAM, TLC) + 1× **Crucial P310 2 TB** (DRAM-less) | T500s are the only DRAM-cached drives → the performance backbone |
| Replication | `size=3`, `min_size=2` | Standard safe replicated config; avoid `size=2/min_size=1` (single-failure data loss) |
| Failure domain | `host` | One OSD per host → clean host-level domain |
| Raw / usable | 8 TB raw → **~2.67 TB usable** (~2.2 TB at 85 % nearfull) | 8 TB ÷ 3 replicas |
| Device classing | P310 2 TB stays in the main pool, with **`ceph osd primary-affinity <p310-osd> 0`** | P310 holds replicas and takes write load like any OSD (~1/4 of PGs), but is never elected primary → never serves client reads under normal operation |

### Why these specific drives

- **The 3× T500 are the only primary-grade OSDs** — they have DRAM cache + real TLC, giving
  predictable fsync latency and endurance under Ceph's write-heavy BlueStore. The pool is kept
  T500-homogeneous except for the deliberate 4th OSD.
- **DRAM-less drives are otherwise kept out of Ceph.** NV3 / P310 / Goodram are fine for boot, etcd
  (tiny WAL writes), and local PVs, but as primary OSDs they show poor sustained random-write latency
  and faster wear. The **one** exception is the P310 2 TB as the 4th OSD — accepted purely to buy the
  4th failure domain, and neutralised on reads via `primary-affinity 0`.

### P310 2 TB role during normal vs. degraded operation

`primary-affinity 0` only suppresses the P310 from being elected **primary OSD** (the OSD that
serves client reads). It does **not** remove it from the write path. CRUSH still assigns the P310
as a non-primary replica for roughly 1 in 4 PGs, so every write to those PGs is committed to the
P310 as well as two T500s. The P310 is not a standby — it always participates in writes.

The practical consequence: the P310's DRAM-less HMB design can be the slow leg on writes for those
PGs. This is a constant background cost, not a failure-only concern. In practice BlueStore's
sequential-write pattern is friendly to HMB drives, so the impact is modest, but it is always
present.

In a degraded state (one T500 host down), the P310 host becomes the recovery target for the
orphaned replicas. Once recovery completes, `primary-affinity 0` ensures the P310 still does not
serve client reads even for those freshly re-replicated PGs. If the P310 host itself becomes the
*only* surviving replica holder for a PG (two hosts down simultaneously), Ceph will override
`primary-affinity` and elect it as primary — this is the data-loss-risk scenario to avoid.

### Self-heal behaviour & residual risk

With `size=3` over **4** hosts, losing one host leaves a legal home for the orphaned third replica on
the surviving 4th host → Ceph **self-heals back to full redundancy** while the failed host is still
down. (A 3-host `size=3` cluster cannot do this — it sits degraded until the host returns, and a disk
failure in that window means data loss. The 4th host is what removes that risk.)

**Residual risk:** do not run **two** hosts down simultaneously, and watch for `HEALTH_WARN`.
Capacity is gated by the smallest host and CRUSH weighting; keep pool utilisation conservative.

---

## Growth Path (M90q 2230-slot trick)

The M90q WLAN/2230 slot can be repurposed as a **PCIe x1 boot SSD** (as already done on the M920q),
exiling boot off the fast 2280 slots. This **does not change the recommended 4-host topology** — the
M90q were never slot-starved, and a second OSD crammed into an M90q shares that host's failure domain
(adds raw TB, **zero** added fault tolerance).

Its real value is a **friction-free capacity-first growth path**:

- **Apply the trick, move M90q boot to the 2230 slot, and bank the freed 2280 slots as empty OSD bays.**
  When a 4th/5th T500 is purchased, it drops straight into a full-speed bay — no chassis teardown, no
  boot-disk juggling, no etcd migration. This is how this cluster scales storage: **bigger/more OSDs
  into existing fast bays**, not more chassis.
- **Optional 5-OSD-host variant (extra failure domain now):** relocate etcd off M920q #2 onto M90q #2
  (which gains a spare 2280 via the trick, boot on its 2230), then promote **M920q #2 to a 5th OSD
  host** with a 1 TB drive → 5 failure domains, more rebalance headroom on a host loss, ~3 TB usable.
  Deferred unless the extra domain is wanted immediately.

---

## Kubernetes Scheduling

| Mechanism | Plan |
|-----------|------|
| Labels | `node-role.kubernetes.io/control-plane` (auto); `storage=true` on OSD hosts (Rook `nodeAffinity` target); tier labels `node.homelab/tier=premium\|workhorse\|light` |
| Taints | **Do not blanket-taint the control plane** — MS-A2 is both CP and the premium worker. Optionally taint **only M920q #2** (`control-plane:NoSchedule`, tolerated by system/light add-ons) to keep it lean. **Do not taint OSD nodes** — they are the main workers. |
| Failure domain | Pod anti-affinity across `kubernetes.io/hostname` for HA app replicas |

**Workload placement:**

- **MS-A2 (premium):** RAM-hungry / AI-inference / database / build workloads, plus anything benefiting
  from the **local NVMe scratch** (slot 3) — AI model weights, build cache, Plex transcode. *Note:* the
  9955HX iGPU (Radeon 610M) is weak for hardware transcode — plan on CPU transcode (16C handles several
  streams) or a dedicated GPU for many HW-encoded streams.
- **M90q (workhorse):** general stateful/stateless apps on Ceph-RBD storage.
- **M920q (light):** control plane, monitoring agents, light add-ons — keep heavy workloads off.

---

## 10 GbE Network Design

Reuses the existing `10.200.0.0/24` storage fabric and policy (see [CLUSTER.md](CLUSTER.md)).

- **LACP bond (802.3ad)** across both X520 ports (MS-A2 on its SFP+), **MTU 9000 (jumbo)**, with mgmt
  (`10.60`) and storage (`10.200`) carried as VLANs over the bond. LACP gives 2×10 G aggregate plus
  port-level resilience; per-flow stays capped at 10 G.
- **Converged Ceph public + cluster network** on the storage VLAN. Do **not** physically split into a
  separate Ceph cluster network yet — with 4 NVMe OSDs the bottleneck is the 10 G link itself, and
  splitting prematurely just halves client bandwidth. Revisit only if monitoring shows replication
  saturating the link.
- **All OSD nodes on 10 GbE** (all five have it; OSD hosts mandatory, light CP nodes benefit as
  clients).

---

## Open Decisions / Action Items

1. ✅ **DONE** — MS-A2 slot count confirmed 3×; all slots now populated.
2. ✅ **DONE** — M920q WLAN slot confirmed PCIe/NVMe (both nodes); M920q #1 P310 2TB OSD installed 2026-06-13.
3. ✅ **DONE** — MS-A2 system disk migrated to Kingston NV3 1TB; AirDisk removed. `machine-volumes-1tb` patch added to cp-01 in talconfig.yaml.
4. **Provision M90q #2** — talconfig.yaml complete (WD SN740 boot disk, T500 OSD, MAC confirmed); apply Talos config and join cluster.
5. **Add M920q #1 P310 2TB as Ceph OSD** — drive is physically installed; Rook-Ceph operator needs to discover it and add it as OSD #4 to complete the 4-host failure-domain topology.
6. ✅ **DONE** — M90q WLAN slot confirmed PCIe/NVMe via M90q #2 WD SN740 2230 in WLAN slot.
7. **Future capacity-first scaling:** buy additional T500 2TB drives and drop into banked M90q OSD bays (WLAN slot confirmed viable).
8. ✅ **DONE (2026-06-18)** — X520-DA2 SFP+ 10GbE cards installed and cut over to `bond-storage` on both M90q #1 (cp-02) and M90q #2 (cp-03), closing the gap with the "10 GbE Network Design" section above (previously both ran storage over a 1GbE VLAN trunk — see CLUSTER.md). LACP confirmed (20 Gbit/s aggregate per node); Ceph stayed `HEALTH_OK` with zero pod restarts through the cutover.

---

## Drive Inventory Reference

| Drive | Class | Current location / role |
|-------|-------|-------------------------|
| 3× Crucial T500 2 TB (DRAM, TLC) | Primary OSD | ✅ MS-A2 OSD (nvme0n1, CT2000T500SSD8); ✅ M90q #1 OSD (S/N 25405348D601); ✅ M90q #2 OSD |
| Crucial P310 2 TB (DRAM-less) | Secondary OSD | ✅ **M920q #1** fast slot — OSD #4 (installed 2026-06-13), `primary-affinity 0` |
| Goodram IRDM Pro P44N 1 TB (DRAM-less, Gen4) | Boot | ✅ **M920q #1** WLAN slot — boot SSD |
| Kingston NV3 1 TB (DRAM-less/HMB) | Boot/etcd | ✅ **MS-A2** slot 2 — boot + etcd (S/N 50026B7686F8B787); ✅ M90q #1 slot 2 — boot + etcd (S/N 50026B7383B9B35C); ✅ M920q #2 slot 1 — boot + etcd (S/N 50026B7383B9D0CC) |
| Crucial P310 1 TB (DRAM-less) | Boot/scratch | ✅ **M920q #2** WLAN slot — spare/scratch (CT1000P310SSD2, S/N 25174FD70E4D) |
| WD PC SN740 256 GB (2230, PCIe 4.0) | Boot | ✅ **M90q #2** WLAN slot — boot (SDDQNQD-256G-1001, S/N 22176G805106) |
| Phison E15T OEM 256 GB (PCIe 4.0, HMB) | Scratch | ✅ **MS-A2** slot 3 — local scratch (YSR256GHLCA1-E5C-2, S/N 511240117089012580) |
| AirDisk 128 GB (MAXIO MAP1202, budget) | — | ❌ **Removed** from MS-A2 — physically replaced by NV3 1TB; retired or spare |
