#!/bin/bash
set -e
export AWS_PAGER=""

PREFIX="mission-deh-hof"
INSTANCE_ID="${PREFIX}-rds-postgres"
SG_NAME="${PREFIX}-rds-sg"
SUBNET_GROUP_NAME="${PREFIX}-subnet-group"
LOG_FILE="${PREFIX}-teardown-$(date '+%Y%m%d-%H%M%S').log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

log "Starting teardown of PostgreSQL RDS resources..."

log "Deleting RDS instance: ${INSTANCE_ID}"
aws rds delete-db-instance \
    --db-instance-identifier ${INSTANCE_ID} \
    --skip-final-snapshot \
    --delete-automated-backups \
    2>/dev/null || log "Instance not found or already deleted"

if aws rds describe-db-instances --db-instance-identifier ${INSTANCE_ID} &>/dev/null; then
    log "Waiting for instance deletion..."
    aws rds wait db-instance-deleted --db-instance-identifier ${INSTANCE_ID}
fi

log "Deleting subnet group: ${SUBNET_GROUP_NAME}"
aws rds delete-db-subnet-group --db-subnet-group-name ${SUBNET_GROUP_NAME} 2>/dev/null || log "Subnet group not found or already deleted"

log "Deleting security group: ${SG_NAME}"
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${SG_NAME}" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
if [ "$SG_ID" != "None" ] && [ -n "$SG_ID" ]; then
    aws ec2 delete-security-group --group-id ${SG_ID} 2>/dev/null || log "Security group in use or already deleted"
fi

log ""
log "================================================================================"
log "TEARDOWN COMPLETED!"
log "================================================================================"
log "All RDS PostgreSQL resources have been deleted."
log "================================================================================"
