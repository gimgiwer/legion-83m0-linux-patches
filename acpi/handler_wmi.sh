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

                            # Debounce cooldown window to prevent rapid event spamming and scheduler thrashing
                            sleep 0.6
                        ) 9>/run/fn_q.lock &
                        ;;
                    000000e8)
                        # Fn+R hardware hotkey on Lenovo Legion (Display Refresh Rate Toggle, silent)
                        (
                            flock -n 8 || exit 0

                            logger "Fn+R pressed: toggling display refresh rate"

                            target_user=$(loginctl list-sessions --no-legend 2>/dev/null | awk '$3 != "" {print $3}' | head -n1)
                            target_uid=$(id -u "$target_user" 2>/dev/null || echo 1000)

                            if [ -n "$target_user" ] && [ -d "/run/user/${target_uid}" ]; then
                                wayland_sock=$(find "/run/user/${target_uid}" -maxdepth 1 -name "wayland-*" -printf "%f\n" 2>/dev/null | head -n1)
                                niri_sock=$(ls "/run/user/${target_uid}"/niri.*.sock 2>/dev/null | head -n1)
                                if [ -n "$wayland_sock" ]; then
                                    runuser -u "$target_user" -- env XDG_RUNTIME_DIR="/run/user/${target_uid}" WAYLAND_DISPLAY="$wayland_sock" NIRI_SOCKET="$niri_sock" bash -c '
                                        edp_json=$(niri msg -j outputs 2>/dev/null | jq -r ".[] | select(.name | startswith(\"eDP\"))")
                                        [ -z "$edp_json" ] && exit 0
                                        edp_name=$(echo "$edp_json" | jq -r ".name")
                                        curr_mode_idx=$(echo "$edp_json" | jq -r ".current_mode")
                                        curr_rate=$(echo "$edp_json" | jq -r ".modes[$curr_mode_idx].refresh_rate")
                                        w=$(echo "$edp_json" | jq -r ".modes[$curr_mode_idx].width")
                                        h=$(echo "$edp_json" | jq -r ".modes[$curr_mode_idx].height")

                                        max_rate=$(echo "$edp_json" | jq -r "[.modes[] | select(.width == $w and .height == $h)] | map(.refresh_rate) | max")
                                        max_hz=$((max_rate / 1000))

                                        if [ "$curr_rate" -ge 120000 ]; then
                                            niri msg output "$edp_name" mode "${w}x${h}@60.000"
                                        else
                                            niri msg output "$edp_name" mode "${w}x${h}@${max_hz}.000"
                                        fi
                                    ' >/dev/null 2>&1
                                fi
                            fi

                            # Debounce cooldown window
                            sleep 0.6
                        ) 8>/run/fn_r.lock &
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
