-- Create database if not exists
CREATE DATABASE IF NOT EXISTS app_db;

-- Grant privileges
GRANT ALL PRIVILEGES ON app_db.* TO 'root'@'%';
FLUSH PRIVILEGES; 