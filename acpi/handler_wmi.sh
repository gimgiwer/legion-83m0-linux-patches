# Snippet for /etc/acpi/handler.sh inside the main case "$1" in ... esac:
    wmi)
        case "$2" in
            PNP0C14:02)
                case "$3" in
                    000000e3)
                        # Fn+Q hardware hotkey on Lenovo Legion (Power Profile Cycle)
                        (
                            flock -n 9 || exit 0

                            logger "Fn+Q pressed: cycling power profile"

                            # Deterministic active seat0 user session lookup via loginctl JSON
                            read -r target_user target_uid < <(loginctl list-sessions --json=short 2>/dev/null | jq -r '.[] | select(.class == "user" and .seat == "seat0") | "\(.user) \(.uid)"' | head -n1)
                            notified=false

                            # Trigger Noctalia OSD and profile switch inside active Wayland session
                            if [ -n "$target_user" ] && [ -n "$target_uid" ] && [ -d "/run/user/${target_uid}" ]; then
                                wayland_sock=$(find "/run/user/${target_uid}" -maxdepth 1 -type s -name "wayland-*" -printf "%f\n" 2>/dev/null | head -n1)
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

                            # Debounce cooldown window to prevent rapid event spamming and scheduler thrashing
                            sleep 0.6
                        ) 9>/run/fn_q.lock &
                        ;;
                    000000e8)
                        # Lenovo Camera Privacy e-Shutter switch
                        logger "Camera privacy shutter toggled: $3"
                        ;;
                    *)
                        logger "ACPI WMI PNP0C14:02 event: $3"
                        ;;
                esac
                ;;
            *)
                logger "ACPI WMI event received: full=$*"
                ;;
        esac
        ;;
