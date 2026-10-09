"""Original vector skill artwork. No commercial texture extraction or raster edits."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]/'project/assets/skill_icons'
SHAPES={
'sword':'<path d="M85 22L97 27 54 88 42 92 44 80Z" fill="#e6f5ed"/><path d="M35 86L60 104M43 94L26 115" stroke="#d3af5f" stroke-width="8"/>',
'fire':'<path d="M70 15C81 52 112 53 107 83C99 123 27 124 22 86C18 65 35 58 39 36C52 59 44 67 57 73C69 55 51 39 70 15Z" fill="#efae62"/><path d="M72 63C91 90 80 109 58 110C37 99 50 82 72 63Z" fill="#ffead0"/>',
'guard':'<path d="M64 17L102 34 96 84 64 114 32 84 26 34Z" fill="#8dc4ac" stroke="#e9d491" stroke-width="4"/><path d="M64 31V93M42 58H87" stroke="#e9f6da" stroke-width="7"/>',
'heal':'<path d="M35 111C43 83 74 63 86 30M50 81C21 75 25 54 31 45C59 43 66 63 50 81M69 56C70 28 90 20 105 25C106 50 87 68 69 56" fill="#a4d7a5" stroke="#d9e2a9" stroke-width="3"/><path d="M93 86V110M81 98H105" stroke="#ffdeb2" stroke-width="7"/>',
'qi':'<path d="M96 29C73 5 30 26 31 58C32 88 86 73 89 99M31 98C65 133 108 100 104 66C101 44 58 48 55 27" fill="none" stroke="#81d5db" stroke-width="7"/><circle cx="64" cy="65" r="15" fill="#e4f7dc"/>',
'seal':'<path d="M31 17L101 25 93 111 26 103Z" fill="#ddc183" stroke="#f1e5c2" stroke-width="3"/><path d="M61 29L74 36 58 50 77 61 48 73 72 88 53 98M40 59L84 61" fill="none" stroke="#a85441" stroke-width="6"/>',
'pressure':'<path d="M25 33C51 73 78 12 103 43M25 60C51 99 77 39 104 69M28 86C52 125 82 67 106 96" fill="none" stroke="#b89fce" stroke-width="8"/><path d="M64 19L57 107" stroke="#ddd2ec" stroke-width="3"/>',
'edge':'<path d="M90 21L96 28 52 94 42 82Z" fill="#fff0b9"/><path d="M41 79L69 100M49 91L33 115M26 54L46 46M91 70L111 63" stroke="#d7b563" stroke-width="7"/>',
'calm':'<circle cx="64" cy="63" r="39" fill="none" stroke="#b5d2b0" stroke-width="4"/><path d="M24 76C43 70 41 45 62 33C80 37 82 73 105 77M48 103L63 72 77 103" fill="none" stroke="#e8d9a3" stroke-width="5"/>',
'robe':'<path d="M46 26L63 33 82 25 111 53 92 70 81 58 88 113 38 113 44 58 32 70 15 52Z" fill="#bfd0c2" stroke="#e7d297" stroke-width="3"/><path d="M47 27L74 76 57 115M82 27L62 60" stroke="#bc8e48" stroke-width="6"/>',
'jade':'<path d="M64 18L92 40 93 87 64 111 35 87 35 40Z" fill="#92cbb3" stroke="#e3cc87" stroke-width="5"/><path d="M51 52C64 30 89 63 65 80C49 89 43 63 59 61" fill="none" stroke="#d9f2d1" stroke-width="5"/>',
'bell':'<path d="M50 28C57 13 74 14 79 29L95 83 109 95H23L37 83Z" fill="#d0b179" stroke="#f0d797" stroke-width="4"/><path d="M46 47H84M40 70H92" stroke="#5c8c82" stroke-width="6"/><circle cx="64" cy="105" r="9" fill="#d6c69e"/>',
}
ITEMS={'sword':'sword','sword_deep':'sword','sword_echo':'sword','ember':'fire','ember_guard':'fire','guard':'guard','guard_spring':'guard','heal':'heal','heal_clean':'heal','qi':'qi','qi_flow':'qi','seal':'seal','seal_burst':'seal','pressure':'pressure','edge':'edge','calm':'calm','iron':'sword','robe':'robe','jade':'jade','blade':'sword','talisman':'seal','bell':'bell','护体':'guard','回春':'heal','侵袭':'fire','蚀骨':'pressure','撕裂':'sword','逆气':'pressure','滞气':'qi','鲸吞':'qi','凝神':'calm','神速':'edge','锋锐':'sword','无常印记':'seal'}
COLORS={'sword':'385d66','fire':'7c4933','guard':'355c4c','heal':'3e5d44','qi':'2e5966','seal':'625337','pressure':'4e435c','edge':'645a37','calm':'40594e','robe':'4b6060','jade':'335a4e','bell':'62573c'}
ROOT.mkdir(parents=True,exist_ok=True)
for name,shape in ITEMS.items():
    accent='<path d="M98 17L111 26 106 43" fill="none" stroke="#fae3ad" stroke-width="3"/>' if '_' in name else ''
    if name=='sword_echo':accent+='<path d="M91 18L46 84" stroke="#9fcbd1" stroke-width="4"/>'
    svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128"><defs><radialGradient id="bg"><stop stop-color="#{COLORS[shape]}"/><stop offset="1" stop-color="#101e23"/></radialGradient></defs><rect x="2" y="2" width="124" height="124" rx="5" fill="url(#bg)"/><circle cx="64" cy="64" r="53" fill="none" stroke="#c7b580" stroke-opacity=".18"/>{SHAPES[shape]}{accent}</svg>'
    (ROOT/(name+'.svg')).write_text(svg,encoding='utf-8')
print('Original skill and Buff icons:',len(ITEMS))
