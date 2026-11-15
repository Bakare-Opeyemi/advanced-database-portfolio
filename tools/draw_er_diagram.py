"""Draw the OpeLat Wallet ER diagram (crow's foot style) as a PNG.

Usage: python3 tools/draw_er_diagram.py portfolio-1-database-design/er-diagram.png
"""
import sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle

NAVY, TEAL, GREY = "#1f3b5c", "#2a7f78", "#6b7280"
ROW = 0.42

# table name -> (x, y_top, width, columns); PK marked with *, FK with >
TABLES = {
    "staff":          (0.3, 15.6, 3.6, ["*staff_id", "full_name", "email (UQ)", "role"]),
    "customers":      (5.2, 15.6, 4.2, ["*customer_id", "phone (UQ)", "first_name, last_name", "date_of_birth", "bvn (UQ)", "state", "kyc_tier", "status"]),
    "kyc_documents":  (0.3, 11.6, 3.6, ["*document_id", ">customer_id", "doc_type", "doc_number", ">verified_by", "verified_at"]),
    "wallets":        (5.2, 10.6, 4.2, ["*wallet_id", "wallet_type", ">customer_id", "currency", "balance", "daily_limit", "status"]),
    "agents":         (11.0, 15.6, 3.8, ["*agent_id", "business_name", "phone (UQ)", "state, lga", ">wallet_id (UQ)"]),
    "billers":        (11.0, 11.4, 3.8, ["*biller_id", "name (UQ)", "category"]),
    "transactions":   (10.6, 8.6, 4.6, ["*txn_id", "reference (UQ)", "txn_type, status, channel", "amount, fee", ">source_wallet_id", ">dest_wallet_id", ">biller_id", ">agent_id", ">reversal_of", "created_at"]),
    "ledger_entries": (5.2, 5.4, 4.2, ["*entry_id", ">txn_id", ">wallet_id", "direction (D/C)", "amount", "balance_after"]),
    "aml_flags":      (10.6, 3.2, 4.6, ["*flag_id", ">txn_id", "rule_code", "risk_score", "status", ">reviewed_by"]),
    "audit_log":      (0.3, 5.4, 3.6, ["*audit_id", "actor, action", "table_name", "record_id", "details (JSONB)"]),
}


def height(cols):
    return (len(cols) + 1) * ROW


def anchor(name, side):
    x, y, w, cols = TABLES[name]
    h = height(cols)
    return {"left": (x, y - h / 2), "right": (x + w, y - h / 2),
            "top": (x + w / 2, y), "bottom": (x + w / 2, y - h)}[side]


fig, ax = plt.subplots(figsize=(13, 12))
ax.set_xlim(0, 15.6); ax.set_ylim(-1.4, 16.4); ax.axis("off")

for name, (x, y, w, cols) in TABLES.items():
    h = height(cols)
    ax.add_patch(Rectangle((x, y - h), w, h, fc="white", ec=NAVY, lw=1.4, zorder=2))
    ax.add_patch(Rectangle((x, y - ROW), w, ROW, fc=NAVY, ec=NAVY, zorder=3))
    ax.text(x + w / 2, y - ROW / 2, name, ha="center", va="center", color="white",
            fontsize=10, fontweight="bold", zorder=4)
    for i, c in enumerate(cols):
        label, color, weight = c, "black", "normal"
        if c.startswith("*"):
            label, color, weight = "PK  " + c[1:], NAVY, "bold"
        elif c.startswith(">"):
            label, color = "FK  " + c[1:], TEAL
        ax.text(x + 0.12, y - ROW * (i + 1.5), label, va="center", fontsize=8.3,
                color=color, fontweight=weight, zorder=4)

# (parent, parent side, child, child side, label)  parent = "one", child = "many"
RELS = [
    ("customers", "bottom", "wallets", "top", "owns  1 : N"),
    ("customers", "left", "kyc_documents", "right", "submits  1 : N"),
    ("staff", "bottom", "kyc_documents", "top", "verifies  1 : N"),
    ("wallets", "right", "agents", "left", "float wallet  1 : 1"),
    ("wallets", "bottom", "ledger_entries", "top", "posted to  1 : N"),
    ("wallets", "right", "transactions", "left", "source / dest  1 : N"),
    ("billers", "bottom", "transactions", "top", "paid via  1 : N"),
    ("transactions", "left", "ledger_entries", "right", "has  1 : N (2+)"),
    ("transactions", "bottom", "aml_flags", "top", "flagged by  1 : N"),
]
for p, ps, c, cs, label in RELS:
    (x1, y1), (x2, y2) = anchor(p, ps), anchor(c, cs)
    ax.annotate("", xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle="-|>", color=GREY, lw=1.2, shrinkA=2, shrinkB=2), zorder=1)
    ax.text(x1 + (x2 - x1) * 0.4, y1 + (y2 - y1) * 0.4, label, fontsize=7.6, color=GREY, ha="center", va="center",
            bbox=dict(fc="white", ec="none", pad=0.6), zorder=5)

ax.text(7.8, 16.2, "OpeLat Wallet ER diagram (PostgreSQL schema olw)", ha="center", fontsize=13,
        fontweight="bold", color=NAVY)
ax.text(7.8, -1.15, "Arrows point from the 'one' side to the 'many' side.  PK = primary key, FK = foreign key, "
        "UQ = unique.  transactions.reversal_of is a self-reference (a reversal points to the original).",
        ha="center", fontsize=8.5, color=GREY)
plt.savefig(sys.argv[1], dpi=170, bbox_inches="tight")
print("saved", sys.argv[1])
