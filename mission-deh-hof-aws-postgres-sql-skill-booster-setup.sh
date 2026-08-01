#!/bin/bash
set -e
export AWS_PAGER=""

PREFIX="mission-deh-hof"
DB_NAME="retail"
MASTER_USERNAME="postgres"
MASTER_PASSWORD="DataEngHub!"
INSTANCE_ID="${PREFIX}-rds-postgres"
SG_NAME="${PREFIX}-rds-sg"
SUBNET_GROUP_NAME="${PREFIX}-subnet-group"
LOG_FILE="${PREFIX}-setup-$(date '+%Y%m%d-%H%M%S').log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

cleanup_on_error() {
    log "ERROR: Setup failed. Starting cleanup..."

    aws rds delete-db-instance \
        --db-instance-identifier ${INSTANCE_ID} \
        --skip-final-snapshot 2>/dev/null && log "Deleted instance: ${INSTANCE_ID}" || true

    aws rds wait db-instance-deleted \
        --db-instance-identifier ${INSTANCE_ID} 2>/dev/null || true

    aws rds delete-db-subnet-group \
        --db-subnet-group-name ${SUBNET_GROUP_NAME} 2>/dev/null && log "Deleted subnet group" || true

    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${SG_NAME}" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null)

    if [ "$SG_ID" != "None" ] && [ -n "$SG_ID" ]; then
        aws ec2 delete-security-group --group-id ${SG_ID} 2>/dev/null && log "Deleted security group" || true
    fi

    log "Cleanup completed."
    exit 1
}

trap cleanup_on_error ERR

log "Starting RDS PostgreSQL Retail Database setup..."
log "Prefix: ${PREFIX}"
log "Database: ${DB_NAME}"
log "Master Username: ${MASTER_USERNAME}"
log "Master Password: ${MASTER_PASSWORD}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
log "AWS Account ID: ${ACCOUNT_ID}"

VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=is-default,Values=true" \
    --query 'Vpcs[0].VpcId' \
    --output text)

if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
    log "ERROR: No default VPC found"
    exit 1
fi
log "Using VPC: ${VPC_ID}"

log "Finding latest PostgreSQL version..."
PG_VERSION=$(aws rds describe-db-engine-versions \
    --engine postgres \
    --query 'DBEngineVersions[].EngineVersion' \
    --output text | tr '\t' '\n' | sort -V | tail -1)

log "Using PostgreSQL version: ${PG_VERSION}"

# Create Security Group
log "Creating security group: ${SG_NAME}"

SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${SG_NAME}" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "")

if [ "$SG_ID" == "None" ] || [ -z "$SG_ID" ]; then
    SG_ID=$(aws ec2 create-security-group \
        --group-name ${SG_NAME} \
        --description "Security group for ${PREFIX} RDS PostgreSQL" \
        --vpc-id ${VPC_ID} \
        --query 'GroupId' --output text)

    aws ec2 authorize-security-group-ingress \
        --group-id ${SG_ID} \
        --protocol tcp \
        --port 5432 \
        --cidr 0.0.0.0/0

    log "Security group created: ${SG_ID}"
else
    log "Security group already exists: ${SG_ID}"
fi

# Create DB Subnet Group
log "Creating DB subnet group: ${SUBNET_GROUP_NAME}"

if ! aws rds describe-db-subnet-groups \
    --db-subnet-group-name ${SUBNET_GROUP_NAME} &>/dev/null; then

    SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'Subnets[0:2].SubnetId' \
        --output text)

    aws rds create-db-subnet-group \
        --db-subnet-group-name ${SUBNET_GROUP_NAME} \
        --db-subnet-group-description "Subnet group for ${PREFIX} RDS PostgreSQL" \
        --subnet-ids ${SUBNET_IDS}

    log "DB subnet group created"
else
    log "DB subnet group already exists"
fi

# Create RDS Instance
log "Creating RDS PostgreSQL instance: ${INSTANCE_ID}"

if ! aws rds describe-db-instances \
    --db-instance-identifier ${INSTANCE_ID} &>/dev/null; then

    aws rds create-db-instance \
        --db-instance-identifier ${INSTANCE_ID} \
        --engine postgres \
        --engine-version ${PG_VERSION} \
        --db-instance-class db.t3.micro \
        --allocated-storage 20 \
        --master-username ${MASTER_USERNAME} \
        --master-user-password ${MASTER_PASSWORD} \
        --db-name ${DB_NAME} \
        --vpc-security-group-ids ${SG_ID} \
        --db-subnet-group-name ${SUBNET_GROUP_NAME} \
        --publicly-accessible

    log "Waiting for instance to be available (5-10 minutes)..."
    aws rds wait db-instance-available \
        --db-instance-identifier ${INSTANCE_ID}

    log "RDS instance created"
else
    log "RDS instance already exists"
fi

ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier ${INSTANCE_ID} \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text)

log "Instance endpoint: ${ENDPOINT}"

# ===============================
# Retail Database SQL Creation
# ===============================

log "Creating retail database schema and data..."


cat > /tmp/retail-db.sql << 'EOF'
-- Categories table
CREATE TABLE categories (
    category_id SERIAL PRIMARY KEY,
    category_name VARCHAR(100) NOT NULL,
    description TEXT
);

-- Suppliers table
CREATE TABLE suppliers (
    supplier_id SERIAL PRIMARY KEY,
    supplier_name VARCHAR(100) NOT NULL,
    contact_name VARCHAR(100),
    phone VARCHAR(20),
    email VARCHAR(100),
    address VARCHAR(200),
    city VARCHAR(50),
    country VARCHAR(50)
);

-- Products table
CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    product_name VARCHAR(100) NOT NULL,
    category_id INTEGER REFERENCES categories(category_id),
    supplier_id INTEGER REFERENCES suppliers(supplier_id),
    unit_price DECIMAL(10,2) NOT NULL,
    units_in_stock INTEGER DEFAULT 0,
    units_on_order INTEGER DEFAULT 0,
    reorder_level INTEGER DEFAULT 0,
    discontinued BOOLEAN DEFAULT FALSE
);

-- Customers table
CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100),
    phone VARCHAR(20),
    address VARCHAR(200),
    city VARCHAR(50),
    state VARCHAR(50),
    postal_code VARCHAR(20),
    country VARCHAR(50),
    registration_date DATE NOT NULL
);

-- Stores table
CREATE TABLE stores (
    store_id SERIAL PRIMARY KEY,
    store_name VARCHAR(100) NOT NULL,
    manager_name VARCHAR(100),
    phone VARCHAR(20),
    address VARCHAR(200),
    city VARCHAR(50),
    state VARCHAR(50),
    country VARCHAR(50)
);

-- Employees table
CREATE TABLE employees (
    employee_id SERIAL PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100),
    phone VARCHAR(20),
    hire_date DATE NOT NULL,
    job_title VARCHAR(50),
    store_id INTEGER REFERENCES stores(store_id),
    salary DECIMAL(10,2)
);

-- Orders table
CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INTEGER REFERENCES customers(customer_id),
    employee_id INTEGER REFERENCES employees(employee_id),
    store_id INTEGER REFERENCES stores(store_id),
    order_date DATE NOT NULL,
    required_date DATE,
    shipped_date DATE,
    ship_address VARCHAR(200),
    ship_city VARCHAR(50),
    ship_postal_code VARCHAR(20),
    ship_country VARCHAR(50),
    shipping_fee DECIMAL(10,2),
    order_status VARCHAR(20)
);

-- Order_items table
CREATE TABLE order_items (
    order_item_id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES orders(order_id),
    product_id INTEGER REFERENCES products(product_id),
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    discount DECIMAL(4,2) DEFAULT 0
);

-- Inventory table
CREATE TABLE inventory (
    inventory_id SERIAL PRIMARY KEY,
    store_id INTEGER REFERENCES stores(store_id),
    product_id INTEGER REFERENCES products(product_id),
    quantity INTEGER NOT NULL,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert Categories
INSERT INTO categories (category_name, description) VALUES
('Electronics', 'Electronic devices and accessories'),
('Clothing', 'Apparel and fashion items'),
('Home & Garden', 'Home improvement and garden supplies'),
('Sports & Outdoors', 'Sports equipment and outdoor gear'),
('Books', 'Books and educational materials'),
('Toys & Games', 'Toys, games, and entertainment'),
('Health & Beauty', 'Health and beauty products'),
('Automotive', 'Auto parts and accessories');

-- Insert Suppliers
INSERT INTO suppliers (supplier_name, contact_name, phone, email, address, city, country) VALUES
('TechSupply Co', 'John Smith', '555-0101', 'john@techsupply.com', '123 Tech St', 'San Francisco', 'USA'),
('Fashion Wholesale', 'Sarah Johnson', '555-0102', 'sarah@fashionwholesale.com', '456 Fashion Ave', 'New York', 'USA'),
('HomeGoods Inc', 'Mike Brown', '555-0103', 'mike@homegoods.com', '789 Home Blvd', 'Chicago', 'USA'),
('Sports Direct', 'Emily Davis', '555-0104', 'emily@sportsdirect.com', '321 Sports Way', 'Los Angeles', 'USA'),
('Book Distributors', 'David Wilson', '555-0105', 'david@bookdist.com', '654 Book Ln', 'Boston', 'USA');

-- Insert Products
INSERT INTO products (product_name, category_id, supplier_id, unit_price, units_in_stock, units_on_order, reorder_level) VALUES
('Smartphone X', 1, 1, 699.99, 150, 50, 30),
('Laptop Pro 15', 1, 1, 1299.99, 75, 25, 20),
('Wireless Earbuds', 1, 1, 149.99, 300, 0, 50),
('Smart Watch', 1, 1, 399.99, 120, 30, 25),
('Men T-Shirt', 2, 2, 29.99, 500, 100, 100),
('Women Jeans', 2, 2, 79.99, 250, 50, 50),
('Running Shoes', 2, 2, 89.99, 200, 0, 40),
('Coffee Maker', 3, 3, 79.99, 100, 20, 20),
('Vacuum Cleaner', 3, 3, 199.99, 60, 15, 15),
('Garden Tools Set', 3, 3, 49.99, 80, 0, 20),
('Yoga Mat', 4, 4, 34.99, 150, 50, 30),
('Camping Tent', 4, 4, 249.99, 40, 10, 10),
('Bicycle', 4, 4, 499.99, 30, 10, 8),
('SQL Mastery Book', 5, 5, 49.99, 200, 0, 40),
('Python Programming', 5, 5, 59.99, 180, 20, 35);

-- Insert Stores
INSERT INTO stores (store_name, manager_name, phone, address, city, state, country) VALUES
('Downtown Store', 'Robert Anderson', '555-1001', '100 Main St', 'New York', 'NY', 'USA'),
('Westside Mall', 'Maria Garcia', '555-1002', '200 West Ave', 'Los Angeles', 'CA', 'USA'),
('Central Plaza', 'William Martinez', '555-1003', '300 Central Blvd', 'Chicago', 'IL', 'USA'),
('Eastside Outlet', 'Linda Rodriguez', '555-1004', '400 East Rd', 'Houston', 'TX', 'USA'),
('Northgate Center', 'Michael Lee', '555-1005', '500 North St', 'Phoenix', 'AZ', 'USA');

-- Insert Employees
INSERT INTO employees (first_name, last_name, email, phone, hire_date, job_title, store_id, salary) VALUES
('Alice', 'Johnson', 'alice.j@retail.com', '555-2001', '2020-01-15', 'Sales Associate', 1, 35000),
('Bob', 'Williams', 'bob.w@retail.com', '555-2002', '2019-06-20', 'Store Manager', 1, 65000),
('Carol', 'Brown', 'carol.b@retail.com', '555-2003', '2021-03-10', 'Cashier', 2, 30000),
('Daniel', 'Davis', 'daniel.d@retail.com', '555-2004', '2020-09-05', 'Sales Associate', 2, 35000),
('Eva', 'Miller', 'eva.m@retail.com', '555-2005', '2018-11-12', 'Store Manager', 2, 65000),
('Frank', 'Wilson', 'frank.w@retail.com', '555-2006', '2021-07-22', 'Stock Clerk', 3, 32000),
('Grace', 'Moore', 'grace.m@retail.com', '555-2007', '2019-04-18', 'Sales Associate', 3, 35000),
('Henry', 'Taylor', 'henry.t@retail.com', '555-2008', '2020-12-01', 'Cashier', 4, 30000),
('Iris', 'Anderson', 'iris.a@retail.com', '555-2009', '2021-02-14', 'Sales Associate', 4, 35000),
('Jack', 'Thomas', 'jack.t@retail.com', '555-2010', '2019-08-30', 'Store Manager', 5, 65000);

-- Insert Customers
INSERT INTO customers (first_name, last_name, email, phone, address, city, state, postal_code, country, registration_date) VALUES
('James', 'Smith', 'james.smith@email.com', '555-3001', '10 Oak St', 'New York', 'NY', '10001', 'USA', '2023-01-15'),
('Mary', 'Johnson', 'mary.j@email.com', '555-3002', '20 Pine Ave', 'Los Angeles', 'CA', '90001', 'USA', '2023-02-20'),
('John', 'Williams', 'john.w@email.com', '555-3003', '30 Maple Dr', 'Chicago', 'IL', '60601', 'USA', '2023-03-10'),
('Patricia', 'Brown', 'patricia.b@email.com', '555-3004', '40 Elm Rd', 'Houston', 'TX', '77001', 'USA', '2023-04-05'),
('Robert', 'Jones', 'robert.j@email.com', '555-3005', '50 Cedar Ln', 'Phoenix', 'AZ', '85001', 'USA', '2023-05-12'),
('Jennifer', 'Garcia', 'jennifer.g@email.com', '555-3006', '60 Birch Way', 'Philadelphia', 'PA', '19101', 'USA', '2023-06-18'),
('Michael', 'Miller', 'michael.m@email.com', '555-3007', '70 Spruce Ct', 'San Antonio', 'TX', '78201', 'USA', '2023-07-22'),
('Linda', 'Davis', 'linda.d@email.com', '555-3008', '80 Willow St', 'San Diego', 'CA', '92101', 'USA', '2023-08-30'),
('William', 'Rodriguez', 'william.r@email.com', '555-3009', '90 Ash Ave', 'Dallas', 'TX', '75201', 'USA', '2023-09-14'),
('Elizabeth', 'Martinez', 'elizabeth.m@email.com', '555-3010', '100 Poplar Dr', 'San Jose', 'CA', '95101', 'USA', '2023-10-25'),
('David', 'Hernandez', 'david.h@email.com', '555-3011', '110 Cherry Rd', 'Austin', 'TX', '73301', 'USA', '2023-11-08'),
('Barbara', 'Lopez', 'barbara.l@email.com', '555-3012', '120 Walnut Ln', 'Jacksonville', 'FL', '32099', 'USA', '2023-12-15'),
('Richard', 'Gonzalez', 'richard.g@email.com', '555-3013', '130 Hickory Way', 'Fort Worth', 'TX', '76101', 'USA', '2024-01-20'),
('Susan', 'Wilson', 'susan.w@email.com', '555-3014', '140 Beech Ct', 'Columbus', 'OH', '43004', 'USA', '2024-02-10'),
('Joseph', 'Anderson', 'joseph.a@email.com', '555-3015', '150 Sycamore St', 'Charlotte', 'NC', '28201', 'USA', '2024-03-05');

-- Insert Orders
INSERT INTO orders (customer_id, employee_id, store_id, order_date, required_date, shipped_date, ship_address, ship_city, ship_postal_code, ship_country, shipping_fee, order_status) VALUES
(1, 1, 1, '2024-01-10', '2024-01-15', '2024-01-12', '10 Oak St', 'New York', '10001', 'USA', 9.99, 'Delivered'),
(2, 4, 2, '2024-01-15', '2024-01-20', '2024-01-17', '20 Pine Ave', 'Los Angeles', '90001', 'USA', 12.99, 'Delivered'),
(3, 7, 3, '2024-01-20', '2024-01-25', '2024-01-22', '30 Maple Dr', 'Chicago', '60601', 'USA', 9.99, 'Delivered'),
(4, 9, 4, '2024-01-25', '2024-01-30', NULL, '40 Elm Rd', 'Houston', '77001', 'USA', 14.99, 'Processing'),
(5, 1, 1, '2024-02-01', '2024-02-06', '2024-02-03', '50 Cedar Ln', 'Phoenix', '85001', 'USA', 9.99, 'Delivered'),
(6, 4, 2, '2024-02-05', '2024-02-10', '2024-02-07', '60 Birch Way', 'Philadelphia', '19101', 'USA', 11.99, 'Delivered'),
(7, 7, 3, '2024-02-10', '2024-02-15', NULL, '70 Spruce Ct', 'San Antonio', '78201', 'USA', 9.99, 'Shipped'),
(8, 9, 4, '2024-02-15', '2024-02-20', '2024-02-17', '80 Willow St', 'San Diego', '92101', 'USA', 13.99, 'Delivered'),
(9, 1, 1, '2024-02-20', '2024-02-25', '2024-02-22', '90 Ash Ave', 'Dallas', '75201', 'USA', 9.99, 'Delivered'),
(10, 4, 2, '2024-02-25', '2024-03-01', NULL, '100 Poplar Dr', 'San Jose', '95101', 'USA', 15.99, 'Processing'),
(1, 1, 1, '2024-03-01', '2024-03-06', '2024-03-03', '10 Oak St', 'New York', '10001', 'USA', 9.99, 'Delivered'),
(11, 7, 3, '2024-03-05', '2024-03-10', '2024-03-07', '110 Cherry Rd', 'Austin', '73301', 'USA', 10.99, 'Delivered'),
(12, 9, 4, '2024-03-10', '2024-03-15', NULL, '120 Walnut Ln', 'Jacksonville', '32099', 'USA', 9.99, 'Shipped'),
(13, 1, 1, '2024-03-15', '2024-03-20', '2024-03-17', '130 Hickory Way', 'Fort Worth', '76101', 'USA', 12.99, 'Delivered'),
(14, 4, 2, '2024-03-20', '2024-03-25', NULL, '140 Beech Ct', 'Columbus', '43004', 'USA', 9.99, 'Processing');

-- Insert Order Items
INSERT INTO order_items (order_id, product_id, quantity, unit_price, discount) VALUES
(1, 1, 1, 699.99, 0.00),
(1, 3, 1, 149.99, 0.05),
(2, 5, 3, 29.99, 0.00),
(2, 6, 1, 79.99, 0.00),
(3, 2, 1, 1299.99, 0.10),
(4, 7, 2, 89.99, 0.00),
(4, 11, 1, 34.99, 0.00),
(5, 8, 1, 79.99, 0.00),
(5, 10, 1, 49.99, 0.00),
(6, 4, 1, 399.99, 0.05),
(7, 14, 2, 49.99, 0.00),
(7, 15, 1, 59.99, 0.00),
(8, 9, 1, 199.99, 0.00),
(9, 12, 1, 249.99, 0.10),
(10, 13, 1, 499.99, 0.00),
(11, 3, 2, 149.99, 0.00),
(12, 5, 5, 29.99, 0.10),
(13, 1, 1, 699.99, 0.00),
(13, 4, 1, 399.99, 0.00),
(14, 7, 1, 89.99, 0.00),
(14, 11, 2, 34.99, 0.00);

-- Insert Inventory
INSERT INTO inventory (store_id, product_id, quantity) VALUES
(1, 1, 30), (1, 2, 15), (1, 3, 60), (1, 4, 25), (1, 5, 100),
(2, 1, 35), (2, 2, 18), (2, 3, 70), (2, 4, 28), (2, 6, 55),
(3, 5, 120), (3, 6, 60), (3, 7, 45), (3, 8, 22), (3, 9, 15),
(4, 10, 18), (4, 11, 35), (4, 12, 10), (4, 13, 8), (4, 14, 45),
(5, 1, 25), (5, 3, 50), (5, 7, 40), (5, 11, 30), (5, 15, 40);
EOF
log "Loading retail database..."

PGPASSWORD=${MASTER_PASSWORD} psql \
    -h ${ENDPOINT} \
    -U ${MASTER_USERNAME} \
    -d ${DB_NAME} \
    -f /tmp/retail-db.sql 2>&1 | tee -a "${LOG_FILE}"

log "Cleaning up temporary files..."
rm -f /tmp/retail-db.sql

log "Retail database loaded successfully!"

log ""
log "================================================================================"
log "SETUP COMPLETED SUCCESSFULLY!"
log "================================================================================"
log "Instance ID: ${INSTANCE_ID}"
log "Endpoint: ${ENDPOINT}"
log "Database: ${DB_NAME}"
log "Username: ${MASTER_USERNAME}"
log "Password: ${MASTER_PASSWORD}"
log "Port: 5432"
log ""
log "Retail database is ready for SQL practice!"
log "Connect via psql:"
log "  psql -h ${ENDPOINT} -U ${MASTER_USERNAME} -d ${DB_NAME}"
log "================================================================================"
