<?php

// la conexion esta e el config.php
include 'config.php';

// conexión a pgbouncer
// $dbconn = pg_connect("host=127.0.0.1 port=6432 dbname=CHECK_USER user=CHECK_USER password=CHECK_USER_PASSWORD");

if($dbconn == null) {
        http_response_code(503);
        echo "Sin conexión a la base de datos";
        exit;
}

$query = "select pg_is_in_recovery();";

$res = pg_query($query);

if($res == null) {
        http_response_code(503);
        echo "Error al ejecutar la query";
        exit;
}

$line = pg_fetch_array($res, null, PGSQL_ASSOC);

if($line == null) {
        http_response_code(503);
        echo "Error leyendo el response de la query";
        exit;
}

$is_in_recovery = $line['pg_is_in_recovery'];

if($is_in_recovery == null) {
        http_response_code(503);
        echo "Error leyendo el campo de la response de la query";
        exit;
}

// comprobacion de si es master
if($_GET['master'] == "true") {
	if($is_in_recovery == "t") {
        	http_response_code(404);
	} else {
        	http_response_code(200);
	}
} else {
	// es sólo ver si esta en marcha, esta, ok
        http_response_code(200);
}

// contestamos con el modo en el que esta en nodo	
if($is_in_recovery == "t") {
	echo "NODO SLAVE\n";
} else {
	echo "NODO MASTER\n";
}

?>
