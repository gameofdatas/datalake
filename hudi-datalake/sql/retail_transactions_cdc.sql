-- Run against Postgres DB: dev, schema: v1
SET search_path TO v1;

-- INSERT
INSERT INTO retail_transactions (tran_id, tran_date, store_id, store_city, store_state, quantity, total)
VALUES (1001, CURRENT_DATE, 11, 'BOSTON', 'MA', 2, 44.50);

-- UPDATE
UPDATE retail_transactions
SET quantity = quantity + 1,
    total = total + 10
WHERE tran_id = 2;

-- DELETE
DELETE FROM retail_transactions
WHERE tran_id = 3;
