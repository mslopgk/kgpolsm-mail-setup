<?php
class admin_button extends rcube_plugin {
    public $task = 'mail|settings|addressbook';

    function init() {
        $rcmail = rcmail::get_instance();
        
        // Only run for HTML responses (not AJAX/JSON)
        if ($rcmail->output && $rcmail->output->type == 'html' && $rcmail->user && $rcmail->user->ID) {
            $username = $rcmail->user->get_username();
            try {
                $pdo = new PDO("mysql:host=127.0.0.1;dbname=mailserver;charset=utf8mb4", "mailuser", "mailpass123");
                $stmt = $pdo->prepare("SELECT is_admin FROM virtual_users WHERE email = ?");
                $stmt->execute([$username]);
                $user = $stmt->fetch(PDO::FETCH_ASSOC);
                
                if ($user && $user['is_admin'] == 1) {
                    $js = "
                        $(document).ready(function() {
                            if ($('#layout-menu .menu').length) {
                                var li = $('<li>').addClass('listitem admin-menu-item');
                                var a = $('<a>').attr('href', 'admin.php')
                                                .attr('target', '_blank')
                                                .addClass('listitem-link')
                                                .css('color', '#d93025')
                                                .text('Admin Panel');
                                li.append(a);
                                $('#layout-menu .menu').append(li);
                            } else {
                                var a = $('<a>').attr('href', 'admin.php')
                                                .attr('target', '_blank')
                                                .addClass('button')
                                                .css({'color': '#d93025', 'font-weight': 'bold', 'padding': '10px'})
                                                .text('Admin Panel');
                                $('.header-links, #taskbar').append(a);
                            }
                        });
                    ";
                    if (method_exists($rcmail->output, 'add_script')) {
                        $rcmail->output->add_script($js, 'foot');
                    }
                }
            } catch (Exception $e) {}
        }
    }
}
