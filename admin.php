<?php
// Bootstrap Roundcube
define('INSTALL_PATH', realpath(__DIR__) . '/');
require_once INSTALL_PATH . 'program/include/iniset.php';

$rcmail = rcmail::get_instance();
if (!$rcmail->user || !$rcmail->user->ID) {
    header("Location: index.php");
    exit;
}

$username = $rcmail->user->get_username();

// Connect to mailserver DB
try {
    $pdo = new PDO("mysql:host=127.0.0.1;dbname=mailserver;charset=utf8mb4", "mailuser", "mailpass123");
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (PDOException $e) {
    die("Database Connection Failed.");
}

// Check if admin
$stmt = $pdo->prepare("SELECT is_admin FROM virtual_users WHERE email = :email");
$stmt->execute(['email' => $username]);
$user = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$user || $user['is_admin'] != 1) {
    die("<h2>Access Denied. You do not have administrative privileges.</h2><a href='index.php'>Return to Mail</a>");
}

// Handle actions
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action'])) {
    $action = $_POST['action'];
    if ($action === 'add_user') {
        $email = $_POST['email'];
        $password = $_POST['password'];
        if (!empty($email) && !empty($password)) {
            $stmt = $pdo->prepare("SELECT id FROM virtual_users WHERE email = :email");
            $stmt->execute(['email' => $email]);
            if (!$stmt->fetch()) {
                $salt = substr(str_shuffle('./ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'), 0, 16);
                $hashed = '{SHA512-CRYPT}' . crypt($password, '$6$' . $salt . '$');
                $stmt = $pdo->prepare("INSERT INTO virtual_users (domain_id, email, password, is_admin, active) VALUES (1, :email, :pw, 0, 1)");
                $stmt->execute(['email' => $email, 'pw' => $hashed]);
            }
        }
    } elseif ($action === 'delete_user') {
        $id = (int)$_POST['id'];
        $stmt = $pdo->prepare("DELETE FROM virtual_users WHERE id = :id");
        $stmt->execute(['id' => $id]);
    } elseif ($action === 'toggle_active') {
        $id = (int)$_POST['id'];
        $new_status = (int)$_POST['status'] ? 0 : 1;
        $stmt = $pdo->prepare("UPDATE virtual_users SET active = :status WHERE id = :id");
        $stmt->execute(['status' => $new_status, 'id' => $id]);
    } elseif ($action === 'toggle_admin') {
        $id = (int)$_POST['id'];
        $new_status = (int)$_POST['status'] ? 0 : 1;
        $stmt = $pdo->prepare("UPDATE virtual_users SET is_admin = :status WHERE id = :id");
        $stmt->execute(['status' => $new_status, 'id' => $id]);
    }
    header("Location: admin.php");
    exit;
}

// Fetch all users
$stmt = $pdo->query("SELECT id, email, is_admin, active FROM virtual_users ORDER BY id DESC");
$users = $stmt->fetchAll(PDO::FETCH_ASSOC);
?>
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Workspace Admin</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background: #f8f9fa; margin: 0; padding: 40px 20px; color: #202124; }
        .container { max-width: 900px; margin: 0 auto; background: #fff; border: 1px solid #dadce0; border-radius: 8px; padding: 40px; box-shadow: 0 1px 3px rgba(60,64,67,0.1); }
        .header { display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #e8eaed; padding-bottom: 20px; margin-bottom: 30px; }
        h1 { margin: 0; font-size: 24px; font-weight: 400; }
        .back-link { color: #1a73e8; text-decoration: none; font-weight: 500; font-size: 14px; }
        .back-link:hover { text-decoration: underline; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th, td { padding: 14px 16px; text-align: left; border-bottom: 1px solid #e8eaed; }
        th { font-size: 12px; color: #5f6368; font-weight: 500; text-transform: uppercase; letter-spacing: 0.5px; }
        td { font-size: 14px; }
        .btn { padding: 8px 16px; border: 1px solid #dadce0; background: #fff; border-radius: 4px; color: #1a73e8; font-weight: 500; cursor: pointer; display: inline-block; font-size: 14px; }
        .btn:hover { background: #f8f9fa; }
        .btn-primary { background: #1a73e8; color: #fff; border: none; }
        .btn-primary:hover { background: #1557b0; box-shadow: 0 1px 2px rgba(60,64,67,0.3); }
        .btn-danger { color: #d93025; }
        .btn-sm { padding: 6px 12px; font-size: 12px; margin-right: 4px; }
        .form-group { margin-bottom: 15px; }
        .form-group label { display: block; font-size: 12px; color: #5f6368; margin-bottom: 6px; font-weight: 500;}
        .form-control { width: 100%; padding: 10px 14px; border: 1px solid #dadce0; border-radius: 4px; font-size: 14px; box-sizing: border-box; outline: none; }
        .form-control:focus { border-color: #1a73e8; box-shadow: 0 0 0 1px #1a73e8 inset; }
        .add-user-form { background: #f8f9fa; padding: 24px; border-radius: 8px; margin-bottom: 30px; border: 1px solid #e8eaed; }
        .status-badge { display: inline-block; padding: 4px 8px; border-radius: 4px; font-size: 12px; font-weight: 500; }
        .active { background: #e6f4ea; color: #137333; }
        .inactive { background: #fce8e6; color: #c5221f; }
        .admin { background: #e8f0fe; color: #1967d2; }
    </style>
</head>
<body>
<div class="container">
    <div class="header">
        <h1>Admin Console</h1>
        <a href="index.php" class="back-link">&larr; Back to Mailbox</a>
    </div>

    <div class="add-user-form">
        <h3 style="margin-top:0; font-size: 16px; font-weight: 500; margin-bottom: 15px;">Add New Account</h3>
        <form method="POST" style="display: flex; gap: 15px; align-items: flex-end;">
            <input type="hidden" name="action" value="add_user">
            <div class="form-group" style="flex:1; margin:0;">
                <label>Email Address</label>
                <input type="email" name="email" class="form-control" placeholder="username@kgpolsm.cloud" required>
            </div>
            <div class="form-group" style="flex:1; margin:0;">
                <label>Password</label>
                <input type="password" name="password" class="form-control" required>
            </div>
            <button type="submit" class="btn btn-primary">Create User</button>
        </form>
    </div>

    <table>
        <thead>
            <tr>
                <th>Email Address</th>
                <th>Role</th>
                <th>Status</th>
                <th>Actions</th>
            </tr>
        </thead>
        <tbody>
            <?php foreach ($users as $u): ?>
            <tr>
                <td style="font-weight: 500;"><?= htmlspecialchars($u['email']) ?></td>
                <td>
                    <span class="status-badge <?= $u['is_admin'] ? 'admin' : '' ?>"><?= $u['is_admin'] ? 'Admin' : 'User' ?></span>
                </td>
                <td>
                    <span class="status-badge <?= $u['active'] ? 'active' : 'inactive' ?>"><?= $u['active'] ? 'Active' : 'Suspended' ?></span>
                </td>
                <td>
                    <form method="POST" style="display:inline;">
                        <input type="hidden" name="action" value="toggle_active">
                        <input type="hidden" name="id" value="<?= $u['id'] ?>">
                        <input type="hidden" name="status" value="<?= $u['active'] ?>">
                        <button type="submit" class="btn btn-sm"><?= $u['active'] ? 'Suspend' : 'Activate' ?></button>
                    </form>
                    <form method="POST" style="display:inline;">
                        <input type="hidden" name="action" value="toggle_admin">
                        <input type="hidden" name="id" value="<?= $u['id'] ?>">
                        <input type="hidden" name="status" value="<?= $u['is_admin'] ?>">
                        <button type="submit" class="btn btn-sm"><?= $u['is_admin'] ? 'Revoke Admin' : 'Make Admin' ?></button>
                    </form>
                    <?php if ($u['email'] !== $username): ?>
                    <form method="POST" style="display:inline;" onsubmit="return confirm('Delete this account permanently?');">
                        <input type="hidden" name="action" value="delete_user">
                        <input type="hidden" name="id" value="<?= $u['id'] ?>">
                        <button type="submit" class="btn btn-sm btn-danger" style="border-color: #fad2cf;">Delete</button>
                    </form>
                    <?php endif; ?>
                </td>
            </tr>
            <?php endforeach; ?>
        </tbody>
    </table>
</div>
</body>
</html>
