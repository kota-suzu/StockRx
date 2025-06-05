-- Create databases if not exists
CREATE DATABASE IF NOT EXISTS app_db;
CREATE DATABASE IF NOT EXISTS app_test;

-- Grant all privileges to root from any host for development/test
GRANT ALL PRIVILEGES ON app_db.* TO 'root'@'%';
GRANT ALL PRIVILEGES ON app_test.* TO 'root'@'%';

-- Create dedicated test user for CI/test environments (optional)
CREATE USER IF NOT EXISTS 'test_user'@'%' IDENTIFIED BY 'test_password';
GRANT ALL PRIVILEGES ON app_test.* TO 'test_user'@'%';

FLUSH PRIVILEGES; 