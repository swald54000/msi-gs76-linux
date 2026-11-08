/*
 * Correctifs du MSI GS76 Stealth 11UH sous forme de SSDT en ajout seul : aucune
 * adresse de firmware, seulement un objet manquant et une écriture dans un objet
 * existant. Ainsi la table reste valable si le firmware déplace ses régions ACPI.
 */
DefinitionBlock ("", "SSDT", 2, "GS76FX", "GS76FIX", 0x00000001)
{
    External (\_SB.PC00.LPCB.PS2M.I2CT, IntObj)

    // \_SB.IETM._OSC référence \_TZ.ETMD, que le BIOS ne définit jamais :
    // _OSC échoue avec AE_NOT_FOUND et les réglages Intel DTT n'atteignent pas thermald.
    Scope (\_TZ)
    {
        Name (ETMD, One)
    }

    // Masque l'alias PS/2 du pavé tactile I2C-HID (PS2M._STA renvoie 0 quand I2CT vaut 1),
    // comme le fait Windows par la _DSM de HIDD. Code de niveau module : exécuté au
    // chargement de la table, avant que l'énumération PNP n'évalue PS2M._STA.
    \_SB.PC00.LPCB.PS2M.I2CT = One
}
