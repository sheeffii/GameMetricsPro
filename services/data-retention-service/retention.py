"""
Data Retention Service
- Scheduled archival of old data
- S3 integration for long-term storage
- Audit logging
- GDPR compliance automation
"""

import json
import logging
import os
import sys
from datetime import datetime, timedelta
from typing import List, Dict, Any

import psycopg2
import boto3
from botocore.exceptions import ClientError

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class DataRetentionService:
    """Handle data retention, archival, and GDPR compliance"""
    
    def __init__(self):
        """Initialize database and S3 clients"""
        self.db_params = self._get_db_params()
        self.s3_client = self._init_s3_client()
        self.s3_bucket = os.getenv('S3_BUCKET', 'gamemetrics-archive')
        
        # Retention policies (days)
        self.retention_policies = {
            'player_events': int(os.getenv('RETENTION_EVENTS_DAYS', '90')),
            'player_statistics': int(os.getenv('RETENTION_STATS_DAYS', '365')),
            'notifications': int(os.getenv('RETENTION_NOTIFICATIONS_DAYS', '30')),
        }
    
    def _get_db_params(self) -> Dict[str, str]:
        """Get database parameters"""
        return {
            'host': os.getenv('DB_HOST', 'localhost'),
            'port': os.getenv('DB_PORT', '5432'),
            'database': os.getenv('DB_NAME', 'gamemetrics'),
            'user': os.getenv('DB_USER', 'postgres'),
            'password': os.getenv('DB_PASSWORD', ''),
        }
    
    def _init_s3_client(self):
        """Initialize S3 client"""
        try:
            return boto3.client(
                's3',
                aws_access_key_id=os.getenv('AWS_ACCESS_KEY_ID'),
                aws_secret_access_key=os.getenv('AWS_SECRET_ACCESS_KEY'),
                region_name=os.getenv('AWS_REGION', 'us-east-1'),
            )
        except Exception as e:
            logger.error(f"Failed to initialize S3 client: {e}")
            return None
    
    def archive_table(self, table_name: str, retention_days: int):
        """Archive old data from a table to S3"""
        cutoff_date = datetime.utcnow() - timedelta(days=retention_days)
        
        try:
            conn = psycopg2.connect(**self.db_params)
            cur = conn.cursor()
            
            # Query old records
            if table_name == 'player_events':
                cur.execute("""
                    SELECT * FROM player_events
                    WHERE timestamp < %s
                    ORDER BY timestamp
                    LIMIT 10000
                """, (cutoff_date,))
            elif table_name == 'player_statistics':
                cur.execute("""
                    SELECT * FROM player_statistics
                    WHERE updated_at < %s
                    ORDER BY updated_at
                    LIMIT 10000
                """, (cutoff_date,))
            else:
                logger.warning(f"Unknown table: {table_name}")
                return
            
            rows = cur.fetchall()
            if not rows:
                logger.info(f"No records to archive for {table_name}")
                return
            
            # Archive to S3
            archive_key = f"archives/{table_name}/{cutoff_date.strftime('%Y-%m-%d')}.json"
            archive_data = json.dumps([dict(row) for row in rows], default=str)
            
            if self.s3_client:
                self.s3_client.put_object(
                    Bucket=self.s3_bucket,
                    Key=archive_key,
                    Body=archive_data.encode('utf-8'),
                    ContentType='application/json',
                )
                logger.info(f"Archived {len(rows)} records from {table_name} to S3: {archive_key}")
            
            # Delete archived records
            if table_name == 'player_events':
                cur.execute("""
                    DELETE FROM player_events
                    WHERE timestamp < %s AND timestamp IN (
                        SELECT timestamp FROM player_events
                        WHERE timestamp < %s
                        ORDER BY timestamp
                        LIMIT 10000
                    )
                """, (cutoff_date, cutoff_date))
            elif table_name == 'player_statistics':
                cur.execute("""
                    DELETE FROM player_statistics
                    WHERE updated_at < %s AND updated_at IN (
                        SELECT updated_at FROM player_statistics
                        WHERE updated_at < %s
                        ORDER BY updated_at
                        LIMIT 10000
                    )
                """, (cutoff_date, cutoff_date))
            
            deleted_count = cur.rowcount
            conn.commit()
            cur.close()
            conn.close()
            
            logger.info(f"Deleted {deleted_count} archived records from {table_name}")
            
            # Audit log
            self._log_audit('archive', table_name, deleted_count, archive_key)
            
        except Exception as e:
            logger.error(f"Error archiving {table_name}: {e}")
            raise
    
    def delete_user_data(self, user_id: str):
        """Delete all user data for GDPR compliance"""
        try:
            conn = psycopg2.connect(**self.db_params)
            cur = conn.cursor()
            
            # Delete from all tables
            tables = ['player_events', 'player_statistics', 'users']
            deleted_counts = {}
            
            for table in tables:
                if table == 'player_events':
                    cur.execute("DELETE FROM player_events WHERE player_id = %s", (user_id,))
                elif table == 'player_statistics':
                    cur.execute("DELETE FROM player_statistics WHERE player_id = %s", (user_id,))
                elif table == 'users':
                    cur.execute("DELETE FROM users WHERE id = %s", (user_id,))
                
                deleted_counts[table] = cur.rowcount
            
            conn.commit()
            cur.close()
            conn.close()
            
            logger.info(f"Deleted all data for user {user_id}: {deleted_counts}")
            
            # Audit log
            self._log_audit('gdpr_delete', 'all', sum(deleted_counts.values()), user_id)
            
        except Exception as e:
            logger.error(f"Error deleting user data: {e}")
            raise
    
    def _log_audit(self, action: str, table: str, count: int, details: str):
        """Log audit trail"""
        audit_entry = {
            'timestamp': datetime.utcnow().isoformat(),
            'action': action,
            'table': table,
            'count': count,
            'details': details,
        }
        
        # In production, write to audit log table or S3
        logger.info(f"AUDIT: {json.dumps(audit_entry)}")
    
    def run_retention_job(self):
        """Run retention job for all tables"""
        logger.info("Starting data retention job...")
        
        for table, retention_days in self.retention_policies.items():
            try:
                logger.info(f"Processing retention for {table} (retention: {retention_days} days)")
                self.archive_table(table, retention_days)
            except Exception as e:
                logger.error(f"Failed to process {table}: {e}")
        
        logger.info("Data retention job completed")


def main():
    """Entry point"""
    service = DataRetentionService()
    
    # Run retention job
    if len(sys.argv) > 1 and sys.argv[1] == 'gdpr-delete':
        if len(sys.argv) < 3:
            logger.error("Usage: python retention.py gdpr-delete <user_id>")
            sys.exit(1)
        user_id = sys.argv[2]
        service.delete_user_data(user_id)
    else:
        service.run_retention_job()


if __name__ == '__main__':
    main()



