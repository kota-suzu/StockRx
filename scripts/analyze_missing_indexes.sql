-- 外部キーに対するインデックスの確認
SELECT 
    tc.TABLE_NAME,
    tc.CONSTRAINT_NAME,
    kcu.REFERENCED_TABLE_NAME,
    kcu.COLUMN_NAME,
    CASE 
        WHEN s.COLUMN_NAME IS NULL THEN 'MISSING INDEX'
        ELSE 'INDEX EXISTS'
    END AS index_status
FROM 
    information_schema.TABLE_CONSTRAINTS tc
    JOIN information_schema.KEY_COLUMN_USAGE kcu ON 
        tc.CONSTRAINT_NAME = kcu.CONSTRAINT_NAME AND
        tc.TABLE_SCHEMA = kcu.TABLE_SCHEMA
    LEFT JOIN information_schema.STATISTICS s ON 
        tc.TABLE_NAME = s.TABLE_NAME AND
        kcu.COLUMN_NAME = s.COLUMN_NAME AND
        tc.TABLE_SCHEMA = s.TABLE_SCHEMA
WHERE 
    tc.TABLE_SCHEMA = 'app_db' AND
    tc.CONSTRAINT_TYPE = 'FOREIGN KEY'
GROUP BY 
    tc.TABLE_NAME, tc.CONSTRAINT_NAME, kcu.COLUMN_NAME
ORDER BY 
    index_status DESC, tc.TABLE_NAME;

-- パフォーマンスが重要なクエリで使用される可能性が高いカラムの分析
SELECT 
    TABLE_NAME,
    COLUMN_NAME,
    DATA_TYPE,
    COLUMN_KEY,
    IS_NULLABLE
FROM 
    information_schema.COLUMNS
WHERE 
    TABLE_SCHEMA = 'app_db' AND
    COLUMN_NAME IN ('created_at', 'updated_at', 'deleted_at', 'status', 'active', 'completed_at', 'requested_at', 'expires_at') AND
    COLUMN_KEY = ''
ORDER BY 
    TABLE_NAME, COLUMN_NAME;