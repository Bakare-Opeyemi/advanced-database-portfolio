"""Draw the proposed MoniWallet distributed deployment (Portfolio 5)."""
import sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

NAVY, TEAL, ORANGE, GREY = "#1f3b5c", "#2a7f78", "#d9822b", "#6b7280"
fig, ax = plt.subplots(figsize=(12, 6.6)); ax.set_xlim(0, 24); ax.set_ylim(0, 14.2); ax.axis("off")

def box(x, y, w, h, text, ec, fc="white", fs=9, bold=False):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02,rounding_size=0.15", fc=fc, ec=ec, lw=1.4))
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center", fontsize=fs, fontweight="bold" if bold else "normal")

def zone(x, y, w, h, title, ec):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.05,rounding_size=0.3", fc="#f6f8fb", ec=ec, lw=1.4, ls="--"))
    ax.text(x + 0.3, y + 0.25, title, fontsize=9.5, fontweight="bold", color=ec)

def arrow(x1, y1, x2, y2, label, col=GREY, ls="-"):
    ax.annotate("", xy=(x2, y2), xytext=(x1, y1), arrowprops=dict(arrowstyle="-|>", color=col, lw=1.5, ls=ls))
    ax.text((x1 + x2) / 2, (y1 + y2) / 2 + 0.25, label, ha="center", fontsize=7.8, color=col,
            bbox=dict(fc="white", ec="none", pad=0.4))

box(1.5, 12.0, 21, 1.3, "Mobile app / USSD gateway / agents  ->  API servers (stateless, in Lagos)", NAVY, "#eef3f9", 10, True)
zone(0.4, 0.4, 14.6, 10.3, "Lagos region (primary site)", NAVY)
zone(15.6, 0.4, 8.0, 10.3, "Abuja region (disaster recovery)", ORANGE)

ax.text(0.9, 9.4, "Availability zone A", fontsize=8.5, color=GREY); ax.text(8.0, 9.4, "Availability zone B", fontsize=8.5, color=GREY)
box(0.9, 6.9, 6.2, 2.2, "PostgreSQL PRIMARY\nwallets, transactions, ledger\n(all money writes)", NAVY, fs=9, bold=True)
box(8.0, 6.9, 6.2, 2.2, "PostgreSQL SYNC replica\nsynchronous_commit = on\n(no committed transfer is lost)", NAVY, fs=9)
box(16.2, 6.9, 6.8, 2.2, "PostgreSQL ASYNC replica\nreports, reconciliation (Q6),\npromoted if Lagos is lost", ORANGE, fs=9)
arrow(7.1, 7.6, 8.0, 7.6, "", NAVY)
ax.text(7.55, 6.55, "WAL\nsync", ha="center", fontsize=7.8, color=NAVY)
arrow(14.2, 8.4, 16.2, 8.4, "", ORANGE, "--")
ax.text(15.2, 9.3, "WAL, async\n(seconds of lag)", ha="center", fontsize=7.8, color=ORANGE)

box(0.9, 1.4, 4.2, 2.2, "MongoDB\nprimary\n(profiles, sessions, events)", TEAL, fs=8.5, bold=True)
box(8.0, 1.4, 4.2, 2.2, "MongoDB\nsecondary", TEAL, fs=8.5)
box(16.2, 1.4, 4.2, 2.2, "MongoDB\nsecondary\n(priority 0.5)", TEAL, fs=8.5)
arrow(5.1, 2.5, 8.0, 2.5, "oplog", TEAL); arrow(12.2, 2.0, 16.2, 2.0, "oplog", TEAL, "--")
ax.text(7.6, 4.3, "API servers also read and write profiles, sessions and telemetry here.\nReplica set mwrs: w:\"majority\" writes (2 of 3 nodes), automatic election if the primary fails",
        ha="center", fontsize=8.3, color=TEAL)

arrow(4.0, 12.0, 4.0, 9.1, "all money writes", NAVY)
arrow(19.6, 12.0, 19.6, 9.1, "read-only reports", ORANGE, "--")
ax.text(12, -0.35, "Both regions are in Nigeria, so customer personal data stays in the country (Nigeria Data Protection Act 2023).", ha="center", fontsize=8.5, color=GREY)
ax.set_ylim(-0.8, 14.2)
ax.set_title("Proposed MoniWallet deployment: replication for availability, regions for disaster recovery",
             fontsize=11, fontweight="bold", color=NAVY)
plt.savefig(sys.argv[1], dpi=170, bbox_inches="tight"); print("saved", sys.argv[1])
