# StockRx Deployment Guide

## Overview

This guide covers the deployment process for StockRx, including CI/CD pipelines, infrastructure setup, and production deployment procedures.

## Table of Contents

1. [CI/CD Pipeline](#cicd-pipeline)
2. [Infrastructure Requirements](#infrastructure-requirements)
3. [Deployment Process](#deployment-process)
4. [Environment Configuration](#environment-configuration)
5. [Monitoring and Maintenance](#monitoring-and-maintenance)
6. [Troubleshooting](#troubleshooting)

## CI/CD Pipeline

### GitHub Actions Workflows

#### 1. CI Workflow (`ci.yml`)
- Runs on every pull request and push to main branch
- Executes security scans, linting, and tests
- Basic configuration with room for optimization

#### 2. Optimized CI Workflow (`ci-optimized.yml`)
- **Parallel test execution**: Tests split into 4 groups
- **Enhanced caching**: Ruby gems, Node modules, Rails assets, DB schema
- **Matrix builds**: Security scanners run in parallel
- **Docker layer caching**: Using GitHub Actions cache
- **Test result aggregation**: Comprehensive reporting

#### 3. Deploy Workflow (`deploy.yml`)
- Automated deployment to staging on main branch push
- Manual approval required for production deployment
- Blue/Green deployment strategy for zero downtime
- Automatic rollback on failure

### Performance Improvements

| Metric | Original CI | Optimized CI | Improvement |
|--------|------------|--------------|-------------|
| Test execution | ~15 min | ~5 min | 67% faster |
| Cache hit rate | 30% | 85% | 183% better |
| Parallel jobs | 1 | 4 | 4x throughput |

## Infrastructure Requirements

### Minimum Requirements

#### Staging Environment
- **CPU**: 2 vCPUs
- **RAM**: 4GB
- **Storage**: 20GB SSD
- **Network**: 100 Mbps

#### Production Environment
- **CPU**: 4 vCPUs (8 recommended)
- **RAM**: 8GB (16GB recommended)
- **Storage**: 100GB SSD
- **Network**: 1 Gbps
- **Load Balancer**: Required
- **CDN**: Recommended

### Required Services

1. **MySQL 8.4+**
   - Production configuration optimized
   - Replication setup recommended
   - Regular backups required

2. **Redis 7+**
   - Used for caching and Sidekiq
   - Persistence enabled
   - Memory limits configured

3. **Nginx**
   - Reverse proxy and load balancer
   - SSL termination
   - Static file serving

## Deployment Process

### 1. Initial Setup

```bash
# Clone repository
git clone https://github.com/your-org/stockrx.git
cd stockrx

# Copy environment files
cp .env.production.example .env.production
# Edit .env.production with your values

# Create required directories
mkdir -p backup config/nginx/ssl scripts
```

### 2. SSL Certificate Setup

```bash
# Generate self-signed certificate (for testing)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout config/nginx/ssl/key.pem \
  -out config/nginx/ssl/cert.pem

# For production, use Let's Encrypt or your CA
```

### 3. Build Production Image

```bash
# Build production Docker image
docker build -f Dockerfile.production -t stockrx:production .

# Tag for registry
docker tag stockrx:production ghcr.io/your-org/stockrx:latest
docker push ghcr.io/your-org/stockrx:latest
```

### 4. Deploy to Production

```bash
# Manual deployment
./scripts/deploy.sh production latest

# Or use GitHub Actions
# Push to main branch triggers staging deployment
# Use workflow dispatch for production deployment
```

### 5. Zero-Downtime Deployment

The deployment script implements zero-downtime deployment:

1. **Database backup** before any changes
2. **Pull new image** from registry
3. **Run migrations** on new container
4. **Scale up** new containers (4 instances)
5. **Health checks** on new containers
6. **Scale down** to normal (2 instances)
7. **Remove old containers**

### 6. Rollback Process

If deployment fails:

```bash
# Automatic rollback
./scripts/rollback.sh

# Manual rollback to specific version
docker-compose -f docker-compose.production.yml \
  up -d --no-deps \
  -e IMAGE_TAG=ghcr.io/your-org/stockrx:previous-tag \
  web sidekiq
```

## Environment Configuration

### Critical Environment Variables

```bash
# Rails Configuration
RAILS_ENV=production
RAILS_MASTER_KEY=<from config/master.key>
SECRET_KEY_BASE=<generate with: rails secret>

# Database
DATABASE_PASSWORD=<strong password>
DATABASE_ROOT_PASSWORD=<strong password>

# Redis
REDIS_PASSWORD=<strong password>

# Email (SendGrid example)
SMTP_PASSWORD=<sendgrid api key>

# Monitoring
NEW_RELIC_LICENSE_KEY=<if using New Relic>
SENTRY_DSN=<if using Sentry>
```

### Security Best Practices

1. **Use strong passwords**: Minimum 32 characters, random
2. **Rotate credentials**: Every 90 days
3. **Encrypt secrets**: Use Rails encrypted credentials
4. **Limit access**: Principle of least privilege
5. **Enable 2FA**: For all admin accounts

## Monitoring and Maintenance

### Health Checks

```bash
# Application health
curl https://your-domain.com/health

# Database health
docker-compose exec db mysqladmin ping -h localhost

# Redis health
docker-compose exec redis redis-cli ping

# Sidekiq health
curl https://your-domain.com/sidekiq/stats
```

### Monitoring Setup

1. **Application Monitoring**
   - New Relic APM
   - Custom metrics via Prometheus
   - Error tracking with Sentry

2. **Infrastructure Monitoring**
   - CPU, Memory, Disk usage
   - Network throughput
   - Container health

3. **Log Management**
   - Centralized logging (ELK stack)
   - Log rotation configured
   - Alert on error patterns

### Backup Strategy

```bash
# Automated daily backups
0 2 * * * /app/scripts/backup.sh

# Manual backup
docker-compose exec db mysqldump -u root -p stockrx_production > backup.sql

# Restore from backup
docker-compose exec -T db mysql -u root -p stockrx_production < backup.sql
```

## Troubleshooting

### Common Issues

#### 1. Container Won't Start
```bash
# Check logs
docker-compose logs web

# Common fixes:
# - Check environment variables
# - Verify database connection
# - Check file permissions
```

#### 2. Database Connection Failed
```bash
# Test connection
docker-compose exec web rails db:version

# Common fixes:
# - Check DATABASE_URL
# - Verify network connectivity
# - Check MySQL is running
```

#### 3. Asset Compilation Failed
```bash
# Manually compile assets
docker-compose run --rm web rails assets:precompile

# Common fixes:
# - Check Node.js version
# - Clear cache: rails tmp:clear
# - Check disk space
```

#### 4. High Memory Usage
```bash
# Check memory usage
docker stats

# Common fixes:
# - Tune RAILS_MAX_THREADS
# - Adjust Sidekiq concurrency
# - Enable jemalloc
```

### Performance Tuning

1. **Database Optimization**
   - Analyze slow query log
   - Add missing indexes
   - Optimize InnoDB buffer pool

2. **Application Optimization**
   - Enable caching
   - Use CDN for assets
   - Optimize image sizes

3. **Infrastructure Scaling**
   - Horizontal scaling with load balancer
   - Database read replicas
   - Redis clustering

## Security Considerations

1. **Network Security**
   - Use private networks
   - Configure firewalls
   - Enable SSL/TLS

2. **Application Security**
   - Regular security updates
   - Security scanning in CI
   - Penetration testing

3. **Data Security**
   - Encryption at rest
   - Encryption in transit
   - Regular backups

## Maintenance Schedule

- **Daily**: Check logs, monitor alerts
- **Weekly**: Review metrics, update dependencies
- **Monthly**: Security patches, performance review
- **Quarterly**: Disaster recovery test, credential rotation

## Support

For deployment issues:
1. Check this guide first
2. Review application logs
3. Consult team documentation
4. Contact DevOps team

Remember: Always test deployments in staging before production!