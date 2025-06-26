-- 重複インデックスの検査
SELECT 
    t1.TABLE_NAME,
    t1.INDEX_NAME AS redundant_index,
    t1.COLUMN_NAME AS redundant_columns,
    t2.INDEX_NAME AS dominant_index,
    t2.COLUMN_NAME AS dominant_columns
FROM 
    information_schema.STATISTICS t1
    INNER JOIN information_schema.STATISTICS t2 ON 
        t1.TABLE_SCHEMA = t2.TABLE_SCHEMA AND
        t1.TABLE_NAME = t2.TABLE_NAME AND
        t1.COLUMN_NAME = t2.COLUMN_NAME AND
        t1.INDEX_NAME != t2.INDEX_NAME
WHERE 
    t1.TABLE_SCHEMA = 'app_db' AND
    t1.SEQ_IN_INDEX = 1 AND
    t2.SEQ_IN_INDEX = 1
ORDER BY 
    t1.TABLE_NAME, t1.INDEX_NAME;

-- 未使用インデックスの候補（カーディナリティが低い）
SELECT 
    TABLE_NAME,
    INDEX_NAME,
    COLUMN_NAME,
    CARDINALITY,
    (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = s.TABLE_SCHEMA AND TABLE_NAME = s.TABLE_NAME) as total_rows,
    ROUND((CARDINALITY / (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = s.TABLE_SCHEMA AND TABLE_NAME = s.TABLE_NAME)) * 100, 2) as selectivity_percent
FROM 
    information_schema.STATISTICS s
WHERE 
    TABLE_SCHEMA = 'app_db' AND
    INDEX_NAME != 'PRIMARY' AND
    CARDINALITY IS NOT NULL AND
    CARDINALITY < 10
ORDER BY 
    CARDINALITY ASC;

-- 複合インデックスの効率性チェック
SELECT 
    TABLE_NAME,
    INDEX_NAME,
    GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS columns,
    COUNT(*) AS column_count,
    MAX(CARDINALITY) AS max_cardinality
FROM 
    information_schema.STATISTICS
WHERE 
    TABLE_SCHEMA = 'app_db' AND
    INDEX_NAME != 'PRIMARY'
GROUP BY 
    TABLE_NAME, INDEX_NAME
HAVING 
    COUNT(*) > 1
ORDER BY 
    TABLE_NAME, column_count DESC;