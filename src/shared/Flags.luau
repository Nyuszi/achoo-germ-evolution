-- All 195 countries (193 UN members + Vatican City + Palestine) for the flag skins.
-- The flag picture is the flag emoji, made from the two-letter country code.
-- Keep this file plain Lua.
local Flags = {}

Flags.Continents = {
	{ Id = "Africa", Name = "Africa" },
	{ Id = "Asia", Name = "Asia" },
	{ Id = "Europe", Name = "Europe" },
	{ Id = "NorthAmerica", Name = "North & Central America" },
	{ Id = "SouthAmerica", Name = "South America" },
	{ Id = "Oceania", Name = "Oceania" },
}

local DATA = [[
DZ Algeria;Africa
AO Angola;Africa
BJ Benin;Africa
BW Botswana;Africa
BF Burkina Faso;Africa
BI Burundi;Africa
CV Cape Verde;Africa
CM Cameroon;Africa
CF Central African Republic;Africa
TD Chad;Africa
KM Comoros;Africa
CG Congo;Africa
CD DR Congo;Africa
CI Côte d'Ivoire;Africa
DJ Djibouti;Africa
EG Egypt;Africa
GQ Equatorial Guinea;Africa
ER Eritrea;Africa
SZ Eswatini;Africa
ET Ethiopia;Africa
GA Gabon;Africa
GM Gambia;Africa
GH Ghana;Africa
GN Guinea;Africa
GW Guinea-Bissau;Africa
KE Kenya;Africa
LS Lesotho;Africa
LR Liberia;Africa
LY Libya;Africa
MG Madagascar;Africa
MW Malawi;Africa
ML Mali;Africa
MR Mauritania;Africa
MU Mauritius;Africa
MA Morocco;Africa
MZ Mozambique;Africa
NA Namibia;Africa
NE Niger;Africa
NG Nigeria;Africa
RW Rwanda;Africa
ST São Tomé and Príncipe;Africa
SN Senegal;Africa
SC Seychelles;Africa
SL Sierra Leone;Africa
SO Somalia;Africa
ZA South Africa;Africa
SS South Sudan;Africa
SD Sudan;Africa
TZ Tanzania;Africa
TG Togo;Africa
TN Tunisia;Africa
UG Uganda;Africa
ZM Zambia;Africa
ZW Zimbabwe;Africa
AF Afghanistan;Asia
AM Armenia;Asia
AZ Azerbaijan;Asia
BH Bahrain;Asia
BD Bangladesh;Asia
BT Bhutan;Asia
BN Brunei;Asia
KH Cambodia;Asia
CN China;Asia
CY Cyprus;Asia
GE Georgia;Asia
IN India;Asia
ID Indonesia;Asia
IR Iran;Asia
IQ Iraq;Asia
IL Israel;Asia
JP Japan;Asia
JO Jordan;Asia
KZ Kazakhstan;Asia
KW Kuwait;Asia
KG Kyrgyzstan;Asia
LA Laos;Asia
LB Lebanon;Asia
MY Malaysia;Asia
MV Maldives;Asia
MN Mongolia;Asia
MM Myanmar;Asia
NP Nepal;Asia
KP North Korea;Asia
OM Oman;Asia
PK Pakistan;Asia
PS Palestine;Asia
PH Philippines;Asia
QA Qatar;Asia
SA Saudi Arabia;Asia
SG Singapore;Asia
KR South Korea;Asia
LK Sri Lanka;Asia
SY Syria;Asia
TJ Tajikistan;Asia
TH Thailand;Asia
TL Timor-Leste;Asia
TR Türkiye;Asia
TM Turkmenistan;Asia
AE United Arab Emirates;Asia
UZ Uzbekistan;Asia
VN Vietnam;Asia
YE Yemen;Asia
AL Albania;Europe
AD Andorra;Europe
AT Austria;Europe
BY Belarus;Europe
BE Belgium;Europe
BA Bosnia and Herzegovina;Europe
BG Bulgaria;Europe
HR Croatia;Europe
CZ Czechia;Europe
DK Denmark;Europe
EE Estonia;Europe
FI Finland;Europe
FR France;Europe
DE Germany;Europe
GR Greece;Europe
HU Hungary;Europe
IS Iceland;Europe
IE Ireland;Europe
IT Italy;Europe
LV Latvia;Europe
LI Liechtenstein;Europe
LT Lithuania;Europe
LU Luxembourg;Europe
MT Malta;Europe
MD Moldova;Europe
MC Monaco;Europe
ME Montenegro;Europe
NL Netherlands;Europe
MK North Macedonia;Europe
NO Norway;Europe
PL Poland;Europe
PT Portugal;Europe
RO Romania;Europe
RU Russia;Europe
SM San Marino;Europe
RS Serbia;Europe
SK Slovakia;Europe
SI Slovenia;Europe
ES Spain;Europe
SE Sweden;Europe
CH Switzerland;Europe
UA Ukraine;Europe
GB United Kingdom;Europe
VA Vatican City;Europe
AG Antigua and Barbuda;NorthAmerica
BS Bahamas;NorthAmerica
BB Barbados;NorthAmerica
BZ Belize;NorthAmerica
CA Canada;NorthAmerica
CR Costa Rica;NorthAmerica
CU Cuba;NorthAmerica
DM Dominica;NorthAmerica
DO Dominican Republic;NorthAmerica
SV El Salvador;NorthAmerica
GD Grenada;NorthAmerica
GT Guatemala;NorthAmerica
HT Haiti;NorthAmerica
HN Honduras;NorthAmerica
JM Jamaica;NorthAmerica
MX Mexico;NorthAmerica
NI Nicaragua;NorthAmerica
PA Panama;NorthAmerica
KN Saint Kitts and Nevis;NorthAmerica
LC Saint Lucia;NorthAmerica
VC Saint Vincent and the Grenadines;NorthAmerica
TT Trinidad and Tobago;NorthAmerica
US United States;NorthAmerica
AR Argentina;SouthAmerica
BO Bolivia;SouthAmerica
BR Brazil;SouthAmerica
CL Chile;SouthAmerica
CO Colombia;SouthAmerica
EC Ecuador;SouthAmerica
GY Guyana;SouthAmerica
PY Paraguay;SouthAmerica
PE Peru;SouthAmerica
SR Suriname;SouthAmerica
UY Uruguay;SouthAmerica
VE Venezuela;SouthAmerica
AU Australia;Oceania
FJ Fiji;Oceania
KI Kiribati;Oceania
MH Marshall Islands;Oceania
FM Micronesia;Oceania
NR Nauru;Oceania
NZ New Zealand;Oceania
PW Palau;Oceania
PG Papua New Guinea;Oceania
WS Samoa;Oceania
SB Solomon Islands;Oceania
TO Tonga;Oceania
TV Tuvalu;Oceania
VU Vanuatu;Oceania
]]

Flags.List = {} -- { { Code, Name, Continent } } sorted by name
Flags.ByCode = {}

-- "HU" -> the Hungarian flag emoji (two regional indicator letters)
function Flags.emoji(code)
	if type(code) ~= "string" or #code ~= 2 then
		return ""
	end
	local a, b = string.byte(code, 1, 2)
	return utf8.char(0x1F1E6 + a - 65, 0x1F1E6 + b - 65)
end

for line in string.gmatch(DATA, "[^\n]+") do
	local code, name, continent = string.match(line, "^(%u%u) ([^;]+);(%a+)$")
	if code then
		local f = { Code = code, Name = name, Continent = continent, Sheet = #Flags.List } -- 0-based, data order
		table.insert(Flags.List, f)
		Flags.ByCode[code] = f
	end
end
table.sort(Flags.List, function(a, b)
	return a.Name < b.Name
end)

-- Sharp flag pictures: image sheets drawn by tools/flag-atlas.js (16 flags per 1024 px sheet,
-- 4x4 cells of 256 px, in the data order above). The asset ids come from uploading those sheets;
-- an empty id means "not uploaded yet" and the game falls back to the emoji.
Flags.SheetIds = { "", "", "", "", "", "", "", "", "", "", "", "", "" }
Flags.SheetCell = 256

-- Returns image, ImageRectOffset, ImageRectSize for a flag's picture, or nil (use the emoji)
function Flags.picture(code)
	local f = Flags.ByCode[code]
	local id = f and Flags.SheetIds[f.Sheet // 16 + 1]
	if not id or id == "" then
		return nil
	end
	local i = f.Sheet % 16
	local cell = Flags.SheetCell
	return id, Vector2.new((i % 4) * cell, (i // 4) * cell), Vector2.new(cell, cell)
end

return Flags
