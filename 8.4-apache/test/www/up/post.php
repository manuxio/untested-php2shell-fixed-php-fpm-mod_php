<?php
session_id('testsess'); session_start();
echo "POST keys: ", implode(',', array_keys($_POST)), "\n";
echo "FILES keys: ", implode(',', array_keys($_FILES)), "\n";
echo "SESSION keys: ", implode(',', array_keys($_SESSION)), "\n";
