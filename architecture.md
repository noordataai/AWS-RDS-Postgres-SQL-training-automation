# Architecture Documentation

## Overview

This project automates the creation and deletion of an AWS RDS PostgreSQL
environment specifically designed for SQL training sessions. It provisions
a fully loaded retail database that anyone can connect to and practice
real-world SQL queries immediately.

---

## AWS Resources Created

### 1. RDS PostgreSQL Instance
- **Name**: mission-deh-hof-rds-postgres
- **Engine**: PostgreSQL (latest version — auto-detected)
- **Instance Class**: db.t3.micro (cheapest available)
- **Storage**: 20 GB (gp2)
- **Publicly Accessible**: Yes (required for training connections)
- **Purpose**: The actual database server where SQL practice happens

### 2. Security Group
- **Name**: mission-deh-hof-rds-sg
- **Inbound Rules**: TCP port 5432 (PostgreSQL) open to 0.0.0.0/0
- **Purpose**: Acts as a firewall controlling who can connect to the RDS instance

### 3. DB Subnet Group
- **Name**: mission-deh-hof-subnet-group
- **Subnets**: First 2 subnets from the default VPC
- **Purpose**: Tells RDS which network subnets it is allowed to use

---

## Database Schema

### Entity Relationship Overview

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

### Table Definitions

#### categories
```sql
category_id   SERIAL PRIMARY KEY
category_name VARCHAR(100) NOT NULL
description   TEXT
```

#### suppliers
```sql
supplier_id   SERIAL PRIMARY KEY
supplier_name VARCHAR(100) NOT NULL
contact_name  VARCHAR(100)
phone         VARCHAR(20)
email         VARCHAR(100)
address       VARCHAR(200)
city          VARCHAR(50)
country       VARCHAR(50)
```

#### products
```sql
product_id      SERIAL PRIMARY KEY
product_name    VARCHAR(100) NOT NULL
category_id     INTEGER REFERENCES categories
supplier_id     INTEGER REFERENCES suppliers
unit_price      DECIMAL(10,2) NOT NULL
units_in_stock  INTEGER DEFAULT 0
units_on_order  INTEGER DEFAULT 0
reorder_level   INTEGER DEFAULT 0
discontinued    BOOLEAN DEFAULT FALSE
```

#### customers
```sql
customer_id       SERIAL PRIMARY KEY
first_name        VARCHAR(50) NOT NULL
last_name         VARCHAR(50) NOT NULL
email             VARCHAR(100)
phone             VARCHAR(20)
address           VARCHAR(200)
city              VARCHAR(50)
state             VARCHAR(50)
postal_code       VARCHAR(20)
country           VARCHAR(50)
registration_date DATE NOT NULL
```

#### stores
```sql
store_id     SERIAL PRIMARY KEY
store_name   VARCHAR(100) NOT NULL
manager_name VARCHAR(100)
phone        VARCHAR(20)
address      VARCHAR(200)
city         VARCHAR(50)
state        VARCHAR(50)
country      VARCHAR(50)
```

#### employees
```sql
employee_id SERIAL PRIMARY KEY
first_name  VARCHAR(50) NOT NULL
last_name   VARCHAR(50) NOT NULL
email       VARCHAR(100)
phone       VARCHAR(20)
hire_date   DATE NOT NULL
job_title   VARCHAR(50)
store_id    INTEGER REFERENCES stores
salary      DECIMAL(10,2)
```

#### orders
```sql
order_id         SERIAL PRIMARY KEY
customer_id      INTEGER REFERENCES customers
employee_id      INTEGER REFERENCES employees
store_id         INTEGER REFERENCES stores
order_date       DATE NOT NULL
required_date    DATE
shipped_date     DATE
ship_address     VARCHAR(200)
ship_city        VARCHAR(50)
ship_postal_code VARCHAR(20)
ship_country     VARCHAR(50)
shipping_fee     DECIMAL(10,2)
order_status     VARCHAR(20)
```

#### order_items
```sql
order_item_id SERIAL PRIMARY KEY
order_id      INTEGER REFERENCES orders
product_id    INTEGER REFERENCES products
quantity      INTEGER NOT NULL
unit_price    DECIMAL(10,2) NOT NULL
discount      DECIMAL(4,2) DEFAULT 0
```

#### inventory
```sql
inventory_id SERIAL PRIMARY KEY
store_id     INTEGER REFERENCES stores
product_id   INTEGER REFERENCES products
quantity     INTEGER NOT NULL
last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
```

---

## Setup Flow

```
Start
  │
  ├── Set configuration variables (prefix, db name, credentials)
  ├── Get AWS Account ID automatically
  ├── Find default VPC ID automatically
  ├── Find latest PostgreSQL version automatically
  │
  ├── Create Security Group
  │     └── Open port 5432 to 0.0.0.0/0
  │
  ├── Create DB Subnet Group
  │     └── Using first 2 subnets from default VPC
  │
  ├── Launch RDS PostgreSQL Instance (db.t3.micro, 20GB)
  │     └── Wait 5-10 minutes for instance to be available
  │
  ├── Get RDS Endpoint address
  │
  ├── Create temporary SQL file (/tmp/retail-db.sql)
  │     ├── CREATE TABLE statements (9 tables)
  │     └── INSERT INTO statements (sample data)
  │
  ├── Run SQL file using psql against the RDS instance
  │
  ├── Delete temporary SQL file
  │
  └── Print connection string and summary
```

---

## Teardown Flow

```
Start
  │
  ├── Delete RDS Instance
  │     ├── --skip-final-snapshot (no backup needed)
  │     └── --delete-automated-backups (remove all backups)
  │
  ├── Wait for RDS instance to be fully deleted
  │
  ├── Delete DB Subnet Group
  │
  ├── Find Security Group by name
  │     └── Delete Security Group
  │
  └── Print completion summary
```

---

## Networking Architecture

```
Your Computer
     │
     │ (psql on port 5432)
     ▼
Internet Gateway
     │
     ▼
AWS Default VPC
     │
     ▼
Security Group (mission-deh-hof-rds-sg)
     │  Port 5432 open
     ▼
DB Subnet Group (mission-deh-hof-subnet-group)
     │
     ▼
RDS PostgreSQL Instance (mission-deh-hof-rds-postgres)
     │
     ▼
retail database
     ├── categories
     ├── suppliers
     ├── products
     ├── customers
     ├── stores
     ├── employees
     ├── orders
     ├── order_items
     └── inventory
```

---

## Languages and Tools Used

| Language / Tool | Version | Purpose |
|---|---|---|
| Bash | 4.0+ | Main scripting language |
| AWS CLI | v2 | Creates and deletes AWS resources |
| PostgreSQL | Latest (auto-detected) | Database engine |
| psql | Matches PostgreSQL | Loads SQL schema and data |
| SQL | Standard | Table definitions and data inserts |

---

## Error Handling

### Setup Script
- Uses `set -e` — stops immediately if any command fails
- Uses `trap cleanup_on_error ERR` — triggers automatic cleanup on any error
- Cleanup function deletes: RDS instance → Subnet Group → Security Group
- Checks if resources already exist before creating (idempotent)

### Teardown Script
- Uses `|| log "..."` after each delete command — if resource already deleted, logs warning and continues
- Checks if RDS instance exists before waiting for deletion
- Checks if Security Group ID is valid before attempting deletion

---

## Cost Breakdown

| Resource | Cost |
|---|---|
| db.t3.micro RDS instance | ~$0.016/hour |
| 20GB gp2 storage | ~$0.002/hour |
| Security Group | Free |
| DB Subnet Group | Free |
| **Total per hour** | **~$0.018/hour** |

> A 2-hour training session costs approximately $0.04.
> Always run the teardown script to stop all charges!

---

## Sample Data Summary

| Table | Records Inserted |
|---|---|
| categories | 8 |
| suppliers | 5 |
| products | 15 |
| stores | 5 |
| employees | 10 |
| customers | 15 |
| orders | 14 |
| order_items | 21 |
| inventory | 25 |
| **Total** | **118 records** |
