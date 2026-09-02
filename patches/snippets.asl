/*
 * Lenovo Legion 83M0 (Hawk Point / 15AHP9 / 16AHP9 / R7000) DSDT Snippets
 * Target: Fix s2idle instant wake (Bluetooth) & enable HW breathing LED in sleep
 */

// =============================================================================
// 1. BLUETOOTH SUSPEND WAKE FIX
// Location: Device (\_SB.PCI0.GP17.XHC0.RHUB.PRT5)
// Problem: PRT5 fires GPE03 wake notification, aborting s2idle after ~0.98s.
// Fix: Add or override _PRW to {0, 0} inside Device (PRT5).
// =============================================================================

Device (PRT5)
{
    // ... existing PRT5 content ...

    Name (_PRW, Package (0x02)  // Power Resources for Wake
    {
        Zero, 
        Zero
    })
}


// =============================================================================
// 2. HARDWARE POWER BUTTON LED BREATHING ON SLEEP
// Location: Method (_PTS, 1, NotSerialized) in Root Scope
// Problem: Power button LED does not pulse during s2idle on Linux.
// Fix: Write 0x02 to EC register PCBS (offset 0x42 in ECRAM) via mutex LFCM.
// =============================================================================

Method (_PTS, 1, NotSerialized)  // _PTS: Prepare To Sleep
{
    SPTS (Arg0)
    If ((((Arg0 == 0x03) || (Arg0 == 0x04)) || (Arg0 == One)))
    {
        If (CondRefOf (\_SB.PCI0.LPC0.EC0.LFCM))
        {
            Local0 = Acquire (\_SB.PCI0.LPC0.EC0.LFCM, 0x0FA0)
            If ((Local0 == Zero))
            {
                \_SB.PCI0.LPC0.EC0.PCBS = 0x02
                Release (\_SB.PCI0.LPC0.EC0.LFCM)
            }
        }
    }
    // ... rest of original _PTS ...
}


// =============================================================================
// 3. RESTORE POWER BUTTON LED ON WAKE
// Location: Method (_WAK, 1, NotSerialized) in Root Scope
// Fix: Reset EC register PCBS back to 0x00 on wake.
// =============================================================================

Method (_WAK, 1, NotSerialized)  // _WAK: Wake
{
    If (CondRefOf (\_SB.PCI0.LPC0.EC0.LFCM))
    {
        Local0 = Acquire (\_SB.PCI0.LPC0.EC0.LFCM, 0x0FA0)
        If ((Local0 == Zero))
        {
            \_SB.PCI0.LPC0.EC0.PCBS = Zero
            Release (\_SB.PCI0.LPC0.EC0.LFCM)
        }
    }
    // ... rest of original _WAK ...
}
