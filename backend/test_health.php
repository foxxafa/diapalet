<?php
// Test DB connection
try {
    $pdo = new PDO('mysql:host=diapalet_mysql;dbname=enzo', 'root', '123456');
    echo "Database connection: OK\n";
} catch(Exception $e) {
    echo "Database error: " . $e->getMessage() . "\n";
}

// Test basic response
header('Content-Type: application/json');
echo json_encode([
    'status' => 'ok', 
    'timestamp' => date('Y-m-d H:i:s'),
    'database' => 'Connected'
]);
?> 