# Snippet for /etc/acpi/handler.sh inside the main case "$1" in ... esac:
    wmi)
        case "$2" in
            PNP0C14:02)
                case "$3" in
                    000000e3)
                        # Fn+Q hardware hotkey on Lenovo Legion
                        logger "Fn+Q pressed: cycling power profile"
                        (
                            # Dynamically locate active seat0 user and Wayland display
                            target_user=$(loginctl list-sessions --no-legend 2>/dev/null | awk '$3 != "" {print $3}' | head -n1)
                            target_uid=$(id -u "$target_user" 2>/dev/null || echo 1000)
                            notified=false

                            if [ -n "$target_user" ] && [ -d "/run/user/${target_uid}" ]; then
                                wayland_sock=$(find "/run/user/${target_uid}" -maxdepth 1 -name "wayland-*" -printf "%f\n" 2>/dev/null | head -n1)
                                if [ -n "$wayland_sock" ]; then
                                    if runuser -u "$target_user" -- env XDG_RUNTIME_DIR="/run/user/${target_uid}" WAYLAND_DISPLAY="$wayland_sock" noctalia msg power-cycle >/dev/null 2>&1; then
                                        notified=true
                                    fi
                                fi
                            fi

                            # Fallback to direct powerprofilesctl if compositor notification failed or unavailable
                            if [ "$notified" != "true" ]; then
                                cur=$(powerprofilesctl get 2>/dev/null || echo "balanced")
                                case "$cur" in
                                    power-saver) powerprofilesctl set balanced ;;
                                    balanced)    powerprofilesctl set performance ;;
                                    performance) powerprofilesctl set power-saver ;;
                                    *)           powerprofilesctl set balanced ;;
                                esac
                            fi
                        ) &
                        ;;
                esac
                ;;
        esac
        ;;
