#!/bin/bash

# Fonction pour sauvegarder le contenu dans un fichier
save_to_file() {
    local content="$1"
    local type="$2"
    local user="$3"
    
    # Créer un répertoire de sauvegarde s'il n'existe pas
    local save_dir="/var/log/user_activity_logs"
    mkdir -p "$save_dir"
    
    # Générer un nom de fichier avec date et heure
    local timestamp=$(date "+%d-%m-%Y_%H-%M-%S")
    local filename="${save_dir}/${user}_${type}_${timestamp}.txt"
    
    # Sauvegarder le contenu
    echo "$content" > "$filename"
    
    # Afficher un message de confirmation
    dialog --msgbox "Fichier sauvegardé :\n$filename" 10 50
}

# Fonction pour créer un compte utilisateur
create_user() {
    dialog --inputbox "Entrez le nom d'utilisateur à créer :" 10 40 2> /tmp/username.txt
    username=$(cat /tmp/username.txt)
    
    # Vérifier que le nom d'utilisateur n'est pas vide
    if [ -z "$username" ]; then
        dialog --msgbox "Nom d'utilisateur invalide." 10 40
        return
    fi
    
     # Demander le prénom et nom
    dialog --inputbox "Entrez le prénom et nom complet de l'utilisateur :" 10 40 2> /tmp/fullname.txt
    fullname=$(cat /tmp/fullname.txt)
    
    # Demander le poste de l'utilisateur
    local poste_choices=(
        "Administration" "Informatique" "Comptabilité" 
        "Commercial" "Production" "Marketing" 
        "Ressources Humaines" "Service Client"
    )
    
    local menu_items=()
    for ((i=0; i<${#poste_choices[@]}; i++)); do
        menu_items+=($((i+1)) "${poste_choices[i]}")
    done
    
    local poste_choice=$(dialog --menu "Sélectionnez le poste de l'utilisateur :" 20 50 9 \
        "${menu_items[@]}" \
        2>&1 >/dev/tty)
    
    # Récupérer le poste sélectionné
    if [ -n "$poste_choice" ]; then
        poste="${poste_choices[$((poste_choice-1))]}"
    else
        poste="Non spécifié"
    fi
    
    # Créer l'utilisateur avec le commentaire incluant le nom complet et le poste
    sudo useradd -c "$fullname - $poste" "$username"
    
     # Définir le mot de passe
    dialog --passwordbox "Entrez le mot de passe pour $username :" 10 40 2> /tmp/userpass.txt
    userpass=$(cat /tmp/userpass.txt)
    echo "$username:$userpass" | sudo chpasswd
    
     # Créer le répertoire personnel s'il n'existe pas
    sudo mkhomedir_helper "$username"

     # Message de confirmation détaillé
     dialog --msgbox "Compte créé :\n- Nom d'utilisateur : $username\n- Nom complet : $fullname\n- Poste : $poste\n- Mot de passe : $userpass" 14 50
     
     # Supprimmer le fichier temporaire contenant le mot de passe
    shred -u /tmp/userpass.txt
}

# Fonction pour modifier le mot de passe d'un compte
modify_password() {
    # Demander le nom d'utilisateur
    dialog --inputbox "Entrez le nom d'utilisateur dont vous voulez modifier le mot de passe :" 10 40 2> /tmp/username.txt
    username=$(cat /tmp/username.txt)
    rm -f /tmp/username.txt  # Nettoyer le fichier temporaire
    
    # Vérifier que l'utilisateur existe
    if ! id "$username" >/dev/null 2>&1; then
        dialog --msgbox "Erreur : L'utilisateur $username n'existe pas." 8 40
        return 1
    fi
    
    # Boucle pour la saisie et confirmation du mot de passe
    while true; do
        # Premier mot de passe
        dialog --passwordbox "Entrez le nouveau mot de passe pour $username :" 10 40 2> /tmp/pass1.txt
        pass1=$(cat /tmp/pass1.txt)
        rm -f /tmp/pass1.txt
        
        # Vérifier si le mot de passe est vide
        if [ -z "$pass1" ]; then
            dialog --msgbox "Le mot de passe ne peut pas être vide." 8 40
            continue
        fi
        
        # Confirmation du mot de passe
        dialog --passwordbox "Confirmez le nouveau mot de passe pour $username :" 10 40 2> /tmp/pass2.txt
        pass2=$(cat /tmp/pass2.txt)
        rm -f /tmp/pass2.txt
        
        # Vérifier si les mots de passe correspondent
        if [ "$pass1" = "$pass2" ]; then
            # Changer le mot de passe
            echo "$username:$pass1" | sudo chpasswd
            
            dialog --msgbox "Le mot de passe de l'utilisateur $username a été modifié avec succès." 8 50
            break
        else
            dialog --msgbox "Les mots de passe ne correspondent pas.\nVeuillez réessayer." 8 40
        fi
    done
}

# Fonction pour supprimer un compte utilisateur
delete_user() {
    dialog --inputbox "Entrez le nom d'utilisateur à supprimer :" 10 40 2> /tmp/username.txt
    username=$(cat /tmp/username.txt)
    sudo userdel "$username"
    dialog --msgbox "Le compte utilisateur $username a été supprimé avec succès." 10 40
}

# Fonction pour modifier les droits d'un groupe
modify_group_rights() {
    dialog --inputbox "Entrez le nom du groupe dont vous voulez modifier les utilisateurs :" 10 40 2> /tmp/groupname.txt
    groupname=$(cat /tmp/groupname.txt)
    
    local group_choice=$(dialog --menu "Options pour le groupe $groupname" 15 50 4 \
        1 "Ajouter un utilisateur au groupe" \
        2 "Supprimer un utilisateur du groupe" \
        4 "Annuler" \
        2>&1 >/dev/tty)
    
    if [ $? -ne 0 ]; then
        clear
        exit 0
    fi

    case $group_choice in
        1)
            dialog --inputbox "Entrez le nom de l'utilisateur à ajouter au groupe :" 10 40 2> /tmp/username.txt
            username=$(cat /tmp/username.txt)
            sudo usermod -a -G "$groupname" "$username"
            dialog --msgbox "L'utilisateur $username a été ajouté au groupe $groupname." 10 40
            ;;
        2)
            dialog --inputbox "Entrez le nom de l'utilisateur à supprimer du groupe :" 10 40 2> /tmp/username.txt
            username=$(cat /tmp/username.txt)
            sudo gpasswd -d "$username" "$groupname"
            dialog --msgbox "L'utilisateur $username a été retiré du groupe $groupname." 10 40
            ;;
        3)
            return
            ;;
    esac
}

# Fonction pour afficher le menu des utilisateurs
list_users() {
    # Créer un fichier temporaire pour stocker la liste des utilisateurs
    local temp_file=$(mktemp)
    
    # Récupérer la liste des utilisateurs humains (UID >= 1000 et < 60000)
    getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 {
        printf "%s:%s:%s:%s:%s:%s:%s\n", $1, $2, $3, $4, $5, $6, $7
    }' > "$temp_file"

    # Vérifier si des utilisateurs ont été trouvés
    if [ ! -s "$temp_file" ]; then
        dialog --msgbox "Aucun utilisateur trouvé." 10 40
        return 1
    fi

    # Chemin pour sauvegarder la liste des utilisateurs
    local log_dir="/var/log/user_activity_logs"
    mkdir -p "$log_dir"

    # Afficher la liste avec des boutons d'action
       dialog --extra-button \
        --extra-label "Sauvegarder" \
        --cancel-label "Retour" \
        --textbox "$temp_file" 20 100 \
        2>&1 >/dev/tty

    # Gérer les actions
    local exit_status=$?
    if [ $exit_status -eq 3 ]; then
          # Bouton Sauvegarder
            local timestamp=$(date "+%d-%m-%Y_%H-%M-%S")
            local output_file="${log_dir}/utilisateurs_${timestamp}.txt"
           
        if cp "$temp_file" "$output_file"; then
            dialog --msgbox "Liste sauvegardée dans :\n$output_file" 10 50
            else
             dialog --msgbox "Erreur lors de la sauvegarde du fichier." 10 40
        fi
    fi        
  

    # Nettoyer le fichier temporaire
    rm "$temp_file"
}

# Fonction pour sélectionner et afficher l'historique de l'utilisateur
user_selection() {
    # Créer un fichier temporaire avec la liste des utilisateurs
    local temp_file=$(mktemp)
    
    # Modifier la commande pour formater correctement les données pour dialog
    getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 {
        printf "%s \"%s\" \n", $1, $5
    }' > "$temp_file"
    
    # Sélection de l'utilisateur via dialog
    local user=$(dialog --title "Sélection de l'utilisateur" \
        --menu "Choisissez un utilisateur :" 20 50 10 \
        --file "$temp_file" \
        2>&1 >/dev/tty)

    # Nettoyer le fichier temporaire
    rm "$temp_file"

    # Vérifier si un utilisateur est sélectionné
    if [ -n "$user" ]; then
        history "$user"
    fi
}

# Fonction pour afficher l'historique de l'utilisateur
history() {
    local user="$1"
    
    # Vérifier si l'utilisateur existe
    if ! id "$user" &>/dev/null; then
        dialog --msgbox "Utilisateur $user inexistant." 8 40
        return 1
    fi

    # Boucle du menu
    while true; do
        # Créer un menu avec dialog
        local choix=$(dialog --clear --title "Historique des activités de $user" \
            --menu "Sélectionnez une option:" 50 100 20 \
            1 "Informations générales" \
            2 "Historique des commandes" \
            3 "Historique des connexions" \
            4 "Processus en cours" \
            5 "Activité réseau" \
            6 "Fichiers récents" \
            0 "Quitter" \
            2>&1 >/dev/tty)

        # Gestion du choix
        case $choix in
            1)
                create_info_display "$user" "header"
                ;;
            2)
                create_info_display "$user" "commands"
                ;;
            3)
                create_info_display "$user" "logins"
                ;;
            4)
                create_info_display "$user" "processes"
                ;;
            5)
                create_info_display "$user" "network"
                ;;
            6)
                create_info_display "$user" "files"
                ;;
            0)
                return
                ;;
            *)
                dialog --msgbox "Option invalide" 10 30
                ;;
        esac
    done
}

# Fonction pour créer et afficher les informations avec option de sauvegarde
create_info_display() {
    local user="$1"
    local type="$2"
    local filename=$(mktemp)

    # Vérifier les permissions sudo
    if [ "$(id -u)" -ne 0 ]; then
        dialog --msgbox "Ce script nécessite des privilèges root." 8 40
        return 1
    fi

    # Générer le contenu
    case "$type" in
        "header")
            echo "===== Historique des activités de l'utilisateur $user =====" > "$filename"
            echo "Date : $(date)" >> "$filename"
            echo "Informations de base :" >> "$filename"
            id "$user" >> "$filename"
            getent passwd "$user" | cut -d: -f5 >> "$filename"
            ;;
        "commands")
             echo "--- Historique des commandes récentes de $user ---" > "$filename"
             if [ -f "/home/$user/.bash_history" ]; then
             tail -n 50 "/home/$user/.bash_history" >> "$filename" 2>/dev/null
             else
             echo "Aucun historique de commandes trouvé pour $user" >> "$filename"
            fi
            ;;
        "logins")
            echo "--- Historique des connexions de $user ---" > "$filename"
            last -a | grep "$user" | head -n 20 >> "$filename"
            ;;
        "processes")
            echo "--- Processus en cours de $user ---" > "$filename"
            ps aux | grep "^$user" >> "$filename"
            ;;
        "network")
            echo "--- Activité réseau de $user ---" > "$filename"
            netstat -tuln | grep "$user" >> "$filename"
            ;;
        "files")
            echo "--- Fichiers récemment modifiés par $user ---" > "$filename"
            find "/home/$user" -type f -mtime -7 | head -n 50 >> "$filename"
            
            echo -e "\n=== Fichiers récemment créés par $user ===" >> "$filename"
            find "/home/$user" -type f -ctime -7 | sort -r | head -n 50 >> "$filename"
            ;;
        *)
            dialog --msgbox "Type d'information invalide" 8 40
            rm "$filename"
            return 1
            ;;
    esac

    # Lire le contenu du fichier
    local content=$(cat "$filename")

    # Afficher le contenu avec des options supplémentaires
    local choix
    choix=$(dialog --extra-button \
        --extra-label "Sauvegarder" \
        --textbox "$filename" 20 80 \
        2>&1 >/dev/tty)

    # Gestion du bouton supplémentaire
    local exit_status=$?
    if [ $exit_status -eq 3 ]; then
        # Bouton "Sauvegarder" a été pressé
        save_to_file "$content" "$type" "$user"
    fi

    # Supprimer le fichier temporaire
    rm "$filename"
}

# Fonction du menu principal
menu_principal_users() {
    local choix=$(dialog --stdout \
        --title "Menu Principal de Gestion des Utilisateurs" \
        --menu "Veuillez choisir une option :" 30 100 15 \
        1 "Afficher la liste des utilisateurs" \
        2 "Créer un compte utilisateur" \
        3 "Modifier le mot de passe" \
        4 "Supprimer un compte utilisateur" \
        5 "Modifier les utilisateurs d'un groupe" \
        6 "Historique d'activité d'un utilisateur")
    
    case $choix in
        1)
            list_users
            menu_principal_users
            ;;
        2)    
            create_user
            menu_principal_user
            ;;
        3)
            modify_password
            menu_principal_users
            ;;
        4)
            delete_user
            menu_principal_users
            ;;
        5)
            modify_group_rights
            menu_principal_users
            ;;
        6)
            user_selection
            menu_principal_users
            ;;
        *)
            clear
            exit 0
            ;;
    esac
}

# Point d'entrée du script
main() {
    # Vérifier les privilèges root
    if [ "$(id -u)" -ne 0 ]; then
        echo "Ce script nécessite des privilèges root. Utilisez sudo."
        exit 1
    fi

    # Vérifier la présence de dialog
    if ! command -v dialog &> /dev/null; then
        echo "Le paquet 'dialog' est requis. Installez-le avec : sudo apt-get install dialog"
        exit 1
    fi

    menu_principal_users
}

main
