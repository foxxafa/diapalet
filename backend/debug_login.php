<?php
header('Content-Type: application/json');

// Raw body'yi al
$rawBody = file_get_contents('php://input');
echo "Raw Body: " . $rawBody . "\n";

// JSON decode et
$decoded = json_decode($rawBody, true);
echo "Decoded: " . json_encode($decoded) . "\n";

// Parameters kontrol et
$username = $decoded['username'] ?? 'NOT_FOUND';
$password = $decoded['password'] ?? 'NOT_FOUND';

echo json_encode([
    'raw_body' => $rawBody,
    'decoded' => $decoded,
    'username' => $username,
    'password' => $password
]);
?> 