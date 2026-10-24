CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';
GRANT SELECT, INSERT ON orders.* TO '{{name}}'@'%';
