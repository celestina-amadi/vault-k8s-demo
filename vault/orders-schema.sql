CREATE TABLE IF NOT EXISTS orders (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  item       VARCHAR(100)  NOT NULL,
  amount     DECIMAL(10,2) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO orders (item, amount)
SELECT * FROM (SELECT 'Kubernetes stickers', 4.99 UNION ALL
               SELECT 'Vault hoodie', 49.00 UNION ALL
               SELECT 'Coffee for the on-call engineer', 3.50) AS seed
WHERE NOT EXISTS (SELECT 1 FROM orders);
