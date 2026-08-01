# AWS RDS PostgreSQL SQL Training Automation

Automated Bash scripts to spin up and tear down an AWS RDS PostgreSQL database
loaded with a complete Retail dataset — ready for SQL practice in minutes!

---

## What is the Main Motive Behind These Scripts?

- **SQL Training Environment** — Creates a fully loaded PostgreSQL database on AWS RDS with real retail data so anyone can practice SQL queries immediately without manually setting up anything.
- **Ready-to-Use Dataset** — Automatically creates 9 tables (customers, orders, products, employees, stores etc.) and populates them with realistic sample data — no manual data entry needed.
- **Cost Control** — Uses `db.t3.micro` (cheapest RDS instance), and the teardown script deletes everything after training to stop all charges immediately.
- **Repeatability** — Every student gets the exact same database with the exact same data — consistent training experience every single time.
- **No Manual Setup** — Without this script, setting up an RDS instance, creating tables and inserting data would take 30-45 minutes manually. This does it all in one command.
- **Auto Cleanup on Failure** — If setup fails halfway, it automatically rolls back everything so no orphaned AWS resources are left behind.
- **Paired Lifecycle** — Setup before training, teardown after training — zero ongoing cost when not in use.

---

## Project Overview

This project provides two shell scripts that automate the complete lifecycle of an
AWS RDS PostgreSQL training environment:

- **Setup Script** — Creates all required AWS resources and loads a full retail database in under 15 minutes.
- **Teardown Script** — Destroys all resources after training to avoid unnecessary AWS charges.

---

## What Does the SETUP Script Actually Do?

1. Sets all configuration variables — database name, username, password, instance name at the top.
2. Gets your **AWS Account ID** automatically.
3. Finds your **default VPC** automatically.
4. Finds the **latest PostgreSQL version** available on RDS automatically (no hardcoded version).
5. Creates a **Security Group** with port **5432** open (PostgreSQL port).
6. Creates a **DB Subnet Group** — tells RDS which network subnets it can use.
7. Launches an **RDS PostgreSQL instance** (`db.t3.micro`, 20GB storage, publicly accessible).
8. Waits **5-10 minutes** for the RDS instance to be fully available.
9. Creates a **SQL file** with all table definitions and sample data.
10. Runs that SQL file against the database using the `psql` command.
11. Deletes the temporary SQL file after loading.
12. Prints the **connection string** so you can connect immediately.

---

## What Does the TEARDOWN Script Actually Do?

1. Deletes the **RDS PostgreSQL instance** with `--skip-final-snapshot` (no backup needed for training data).
2. Also passes `--delete-automated-backups` to remove all automated backups.
3. Waits until the instance is **fully deleted** before moving on.
4. Deletes the **DB Subnet Group**.
5. Finds and deletes the **Security Group**.
6. Logs every step with timestamps.
7. Prints a final confirmation when everything is cleaned up.

---

## The Retail Database That Gets Created

The setup script creates a complete **mini retail store database** with 9 tables:

| Table | Description | Sample Records |
|---|---|---|
| `categories` | Product categories | 8 categories (Electronics, Clothing etc.) |
| `suppliers` | Product suppliers | 5 suppliers across the USA |
| `products` | Products with prices and stock | 15 products |
| `customers` | Customer details with addresses | 15 customers |
| `stores` | Store locations | 5 stores across the USA |
| `employees` | Employees assigned to stores | 10 employees |
| `orders` | Orders placed by customers | 14 orders |
| `order_items` | Individual items within orders | 21 order line items |
| `inventory` | Stock levels per store per product | 25 inventory records |

### Table Relationships

```
categories ──< products >── suppliers
                  │
stores ──< inventory >── products
  │
  ├──< employees
  │
  └──< orders >── customers
           │
           └──< order_items >── products
```

### Example SQL Queries You Can Practice

```sql
-- Which customers spent the most?
SELECT c.first_name, c.last_name, SUM(oi.unit_price * oi.quantity) AS total_spent
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY c.customer_id
ORDER BY total_spent DESC;

-- Which products are running low on stock?
SELECT product_name, units_in_stock, reorder_level
FROM products
WHERE units_in_stock <= reorder_level;

-- Which store has the highest revenue?
SELECT s.store_name, SUM(oi.unit_price * oi.quantity) AS revenue
FROM stores s
JOIN orders o ON s.store_id = o.store_id
JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY s.store_id
ORDER BY revenue DESC;
```

---

## Folder Structure

```
aws-rds-postgres-sql-training-automation/
│
├── README.md
├── .gitignore
├── scripts/
│   ├── mission-deh-hof-aws-postgres-sql-skill-booster-setup.sh
│   └── mission-deh-hof-aws-postgres-sql-skill-booster-teardown.sh
└── docs/
    └── architecture.md
```

---

## Prerequisites

Before running these scripts, make sure you have:

- [ ] AWS CLI installed and configured (`aws configure`)
- [ ] AWS account with permissions to create RDS and EC2 (security group) resources
- [ ] `psql` (PostgreSQL client) installed on your machine
- [ ] Bash shell (Linux / Mac / WSL on Windows)
- [ ] Default VPC exists in your AWS account

---

## Usage

### Step 1 — Setup (Before Training Session)

```bash
chmod +x scripts/mission-deh-hof-aws-postgres-sql-skill-booster-setup.sh
./scripts/mission-deh-hof-aws-postgres-sql-skill-booster-setup.sh
```

### Step 2 — Connect to the Database

```bash
psql -h <ENDPOINT> -U postgres -d retail
```

> The endpoint is printed at the end of the setup script output.

### Step 3 — Teardown (After Training Session)

```bash
chmod +x scripts/mission-deh-hof-aws-postgres-sql-skill-booster-teardown.sh
./scripts/mission-deh-hof-aws-postgres-sql-skill-booster-teardown.sh
```

---

## Database Connection Details

| Parameter | Value |
|---|---|
| Engine | PostgreSQL (latest version) |
| Database Name | retail |
| Username | postgres |
| Password | DataEngHub! |
| Port | 5432 |
| Instance Type | db.t3.micro |
| Storage | 20 GB |

---

## Key Features

- **Fully Automated** — Single command to build or destroy the entire environment
- **Cost Optimized** — Uses db.t3.micro (cheapest RDS instance type)
- **Auto Cleanup on Failure** — If setup fails halfway, automatically rolls back all created resources
- **Latest PostgreSQL** — Auto-detects the latest available PostgreSQL version on RDS
- **Idempotent** — Checks if resources already exist before creating them (safe to re-run)
- **Timestamped Logging** — Every step logged to a file for debugging and audit trail
- **Dynamic Configuration** — Auto-detects AWS account ID and default VPC

---

## What Language Are These Scripts Written In?

Both scripts are written in **Bash (Shell Scripting)**

| Tool / Language | Purpose |
|---|---|
| **Bash** | Main scripting language — controls the flow, variables, conditions |
| **AWS CLI** | Talks to AWS to create/delete RDS, security groups, subnet groups |
| **SQL** | Creates the retail database tables and inserts sample data |
| **psql** | PostgreSQL command line client — delivers SQL to the database |

The first line of both scripts `#!/bin/bash` (called a **shebang**) tells the
operating system to use Bash to run the file.

---

## How Were These Scripts Created? What Prompt Was Used?

### Setup Script Prompt:
```
Create a bash script that sets up an AWS RDS PostgreSQL
database for SQL training with the following requirements:

Infrastructure:
- RDS PostgreSQL instance (db.t3.micro, cheapest)
- Auto-detect latest PostgreSQL version (don't hardcode)
- 20GB storage, publicly accessible
- Security group with port 5432 open
- DB subnet group using default VPC subnets

Database Content:
- Create a retail database called "retail"
- Create these tables with proper relationships:
  categories, suppliers, products, customers, stores,
  employees, orders, order_items, inventory
- Insert realistic sample data into all tables
- Use SERIAL for auto-increment primary keys
- Use proper REFERENCES for foreign keys

Safety:
- Use set -e to stop on errors
- If setup fails, auto cleanup all created resources
- Use trap to catch errors
- Check if resources already exist before creating

Logging:
- Log every step with timestamps
- Save to timestamped log file
- Print connection details at the end

Naming: prefix everything with "mission-deh-hof-"
```

### Teardown Script Prompt:
```
Create a bash teardown script that deletes all AWS RDS
resources created by my setup script:

Delete in this order:
1. RDS instance (with --skip-final-snapshot,
   --delete-automated-backups)
2. Wait for instance to be fully deleted
3. Delete DB subnet group
4. Delete security group

Handle errors gracefully - if resource already deleted,
log warning and continue. Don't crash.
Use same naming prefix: "mission-deh-hof-"
```

---

## If You Want to Create a Similar Script in Future

Use this prompt template:

```
Create a bash script that sets up an AWS RDS [DATABASE TYPE]
for [PURPOSE] training with:

1. INFRASTRUCTURE:
   - RDS instance type: [db.t3.micro for cheapest]
   - Engine: [postgres / mysql / mariadb]
   - Storage: [20GB minimum]
   - Publicly accessible: [yes for training]
   - Auto-detect latest engine version

2. DATABASE CONTENT:
   - Database name: [your db name]
   - Tables to create: [list your tables]
   - Relationships: [list foreign keys]
   - Sample data: [describe what data to insert]

3. SAFETY:
   - set -e to stop on errors
   - Auto cleanup on failure using trap
   - Check if resources exist before creating

4. NETWORKING:
   - Security group opening port [5432/3306]
   - DB subnet group using default VPC

5. LOGGING:
   - Timestamps on every log line
   - Save to log file with date in name
   - Print connection string at the end

6. NAMING PREFIX: [your-prefix]-
```

---

## Setup vs Teardown Side by Side

| Step | Setup Script | Teardown Script |
|---|---|---|
| 1 | Get AWS Account ID | Delete RDS Instance |
| 2 | Find default VPC | Wait for full deletion |
| 3 | Find latest PostgreSQL version | Delete DB Subnet Group |
| 4 | Create Security Group (port 5432) | Delete Security Group |
| 5 | Create DB Subnet Group | Print completion summary |
| 6 | Launch RDS Instance | — |
| 7 | Wait for RDS to be available | — |
| 8 | Create SQL schema + data file | — |
| 9 | Load data using psql | — |
| 10 | Print connection string | — |

---

## Workflow

```
Before Training              During Training           After Training
───────────────              ───────────────           ──────────────
Run setup script    →        Connect via psql   →      Run teardown script
(~10-15 minutes)             Practice SQL               (~5 minutes)
                             on retail database         All resources deleted
                                                        Zero ongoing cost
```

---

## Cost Estimate

| Phase | Duration | Estimated Cost |
|---|---|---|
| Setup + Training (2 hrs) | ~2 hours | ~$0.04 |
| Idle (not torn down) | Per day | ~$0.48/day |
| After Teardown | — | $0.00 |

> Always run the teardown script after your session to avoid unnecessary charges!

---

## Comparison With EC2 Unix Training Scripts

| | EC2 Unix Scripts | RDS PostgreSQL Scripts |
|---|---|---|
| **What it creates** | Virtual server (EC2) | Managed database (RDS) |
| **Port opened** | 22 (SSH) | 5432 (PostgreSQL) |
| **Connect using** | `ssh` command | `psql` command |
| **Extra step** | None | Loads SQL schema + data |
| **Wait time** | ~2 minutes | ~10-15 minutes |
| **Cost** | ~$0.01/hr | ~$0.02/hr |
| **Purpose** | Unix/Bash training | SQL training |

---

## Log Files

Both scripts generate timestamped log files:
- `mission-deh-hof-setup-YYYYMMDD-HHMMSS.log`
- `mission-deh-hof-teardown-YYYYMMDD-HHMMSS.log`

---

## Security Notes

- Port 5432 is open to `0.0.0.0/0` (all IPs) — suitable for short training sessions only
- For production use, restrict the CIDR block to your specific IP address
- Never commit database passwords to GitHub
- The teardown script uses `--delete-automated-backups` to ensure no hidden costs remain

---

## Author

**Noor** | [github.com/noordataai](https://github.com/noordataai)

---

## Disclaimer

These scripts are for educational and training purposes only.
Always review scripts before running them in your AWS account.
