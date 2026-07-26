# Running on Oracle Cloud "Always Free" (Ampere A1)

Everything in this repo is cloud-agnostic — `install.sh` just needs SSH
and root on a Debian 12 host. This doc covers the one genuinely-free
option that can match (and in some ways exceed) the original spec: an
Oracle Cloud **Always Free** Ampere A1 Flex instance.

## Is it actually free, forever?

Yes — Oracle's Always Free tier is not a trial credit that expires. As
long as you stay within the Always Free resource limits, it's $0/month
indefinitely, even on a "Pay As You Go" account tier (see "the capacity
problem" below for why upgrading the account tier is still worth doing).

## Spec comparison against the original ask

| | Original spec | Oracle Always Free (Ampere A1) |
|---|---|---|
| CPU | 4 vCPU | Up to **4 OCPU** (Ampere's OCPU ≈ 1 physical core w/ 2 threads-equivalent throughput — comparable or better per-core than a typical shared vCPU) |
| RAM | 8 GB | Up to **24 GB** — 3x the original ask |
| Storage | 100 GB NVMe (local) | Up to **200 GB** block storage total — 2x the ask, but **network-attached SSD, not local NVMe** (see caveat below) |
| Architecture | x86_64 | **arm64/aarch64** — this is the one real deviation, not a "better or worse" tradeoff, just different |
| Public static IPv4 | Yes | Yes, included free |
| IPv6 | Yes | Supported, may need explicit IPv6 CIDR/VCN config depending on region |
| Egress | (droplet-dependent) | 10 TB/month free — generous |

So: **more RAM, more storage, equal-or-better CPU, genuinely free forever** — at the cost of switching from x86_64 to arm64, and local NVMe to network-attached block storage. This repo already accounts for both:

- **Architecture**: `scripts/lib/common.sh`'s `detect_arch` function and every stage that fetches an upstream binary (`06-core-utilities.sh` for eza/zoxide/fastfetch, `09-go-rust-java.sh` for Go) resolve the correct arm64/aarch64 asset automatically — `install.sh` runs unmodified on either architecture. Every apt-installed package (Docker, Postgres, Redis, Nginx, Node, Python, Java, Rust via rustup) already ships arm64 builds upstream.
- **Storage**: `scripts/05-kernel-hardening.sh`'s disk-scheduler check recognizes `sd*`/`vd*`/`xvd*` device naming (what cloud block storage typically shows up as), not just `nvme*`. Functionally nothing else in this repo assumes local NVMe specifically — it's an informational check, not a hard dependency.

The block-storage-vs-local-NVMe difference is a real latency/IOPS
characteristic you can't script around — Oracle's default (free-tier)
"Balanced" volume performance tier is solid for typical Docker/Postgres/
Redis workloads but won't match local NVMe under heavy random I/O. Not
relevant for most dev/small-production workloads; worth knowing if
you're benchmarking a database under load.

## The capacity problem (and the real workaround)

Ampere A1 is Oracle's most popular free shape — in busy regions,
`oci compute instance launch` frequently returns "Out of host capacity"
rather than succeeding on the first try. This is normal, documented
Oracle behavior, not a sign anything is broken. The standard, widely-used
workaround is retrying the launch call across availability domains over
time until capacity frees up — which is exactly what
`cloud/oracle/create-instance-retry.sh` automates.

Things that measurably help alongside the retry script:

- **Upgrade to "Pay As You Go"** account tier (add a payment method) —
  you are not charged as long as you stay within Always Free limits, but
  Oracle deprioritizes pure "Always Free trial" accounts for scarce
  capacity behind PAYG accounts.
- **Try less-popular regions** — capacity is regional; a region other
  than the obvious us-ashburn-1/us-phoenix-1 often has availability
  sooner.
- **Multiple availability domains** — some regions have 3 ADs; the retry
  script cycles through all of them you list, not just one.
- **Patience** — most people get an instance within hours to a couple of
  days of leaving a retry loop running, not weeks.

## Setup steps

1. Create an Oracle Cloud account (oracle.com/cloud/free) — requires a
   card for identity verification even for the free tier; you won't be
   charged while inside Always Free limits.
2. Install the OCI CLI locally (or use Oracle Cloud Shell, which has it
   preinstalled):
   ```
   bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
   oci setup config    # interactive — generates ~/.oci/config + API key
   ```
3. Gather the IDs the retry script needs (compartment, availability
   domains, subnet, image) — the exact `oci` commands for each are
   commented inline in `cloud/oracle/.env.example`.
4. **Debian image availability**: Oracle lists Debian as a platform
   image in most regions/tenancies. Confirm with:
   ```
   oci compute image list --compartment-id <compartment-ocid> \
     --operating-system Debian --shape VM.Standard.A1.Flex
   ```
   If nothing comes back for your tenancy/region, you'd need to import a
   Debian 12 arm64 cloud image as a custom image first (Oracle supports
   custom image import from a QCOW2/VMDK in Object Storage) — out of
   scope for this doc; Oracle's own "Importing a Custom Linux Image"
   guide covers it.
5. ```
   cp cloud/oracle/.env.example cloud/oracle/.env
   vim cloud/oracle/.env
   ./cloud/oracle/create-instance-retry.sh
   ```
6. Once it prints a public IP, proceed exactly as in the main
   `README.md` quick start: SSH in, clone this repo, `.env`, `sudo
   ./install.sh`.

## What doesn't change

Nothing else in this repo is Oracle-specific — the firewall rules,
Docker setup, database hardening, Nginx/Certbot, and backup automation
are identical regardless of which cloud gave you the box. `UFW` still
only opens 22/80/443; make sure Oracle's **Security List / Network
Security Group** on the VCN also allows those (cloud-level firewall
rules sit in front of UFW and block traffic before it reaches the
instance at all — a very common first "why can't I connect" cause on
OCI specifically, since the default VCN security list only opens 22 by
default and you must add 80/443 yourself in the OCI console or via
`oci network security-list update`).
