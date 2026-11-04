"""Generates the Chanchi mascot (Finanzas IA, direction C "Durazno calido") as layered SVGs.

All layers share one 160x140 viewBox so the app can stack them and animate each part:
body (static), eyes (blink), mouth, extras (coin, thought dots, z's, sweat) per mood.
"""
import os, sys

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)

INK = '#2B2118'
TERRA = '#BC4626'
C = dict(shade='#F59C88', body='#FFB4A2', light='#FFD3C7', leg='#FFA48F', back='#F08F7A',
         snout='#FF9F8A', snout_face='#FFAE9B', blush='#FF7F6B')
VB = '0 0 160 140'


def svg(inner, vb=VB):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}">{inner}</svg>\n'


def body(c=C, slot=TERRA, shadow=True):
    s = ''
    if shadow:
        s += f'<ellipse cx="80" cy="128" rx="46" ry="6" fill="{INK}" opacity=".07"/>'
    s += (f'<path d="M36 82C26 80 22 71 28 66C33 62 40 66 37 72C35 75 31 74 31 71" fill="none" '
          f'stroke="{c["back"]}" stroke-width="4.5" stroke-linecap="round"/>'
          f'<path d="M76 52C76 40 82 32 90 32C94 38 94 47 89 54Z" fill="{c["back"]}"/>'
          f'<rect x="50" y="104" width="15" height="19" rx="7" fill="{c["back"]}"/>'
          f'<rect x="94" y="104" width="15" height="19" rx="7" fill="{c["back"]}"/>'
          f'<ellipse cx="80" cy="82" rx="47" ry="35" fill="{c["shade"]}"/>'
          f'<ellipse cx="80" cy="77" rx="45" ry="33" fill="{c["body"]}"/>'
          f'<ellipse cx="63" cy="59" rx="16" ry="7.5" transform="rotate(-18 63 59)" fill="{c["light"]}"/>'
          f'<rect x="60" y="106" width="16" height="19" rx="7" fill="{c["leg"]}"/>'
          f'<rect x="104" y="106" width="16" height="19" rx="7" fill="{c["leg"]}"/>'
          f'<rect x="66" y="46.5" width="24" height="5" rx="2.5" transform="rotate(-4 78 49)" fill="{slot}"/>'
          f'<path d="M90 50C91 38 98 30 106 31C110 37 109 47 102 54Z" fill="{c["leg"]}"/>'
          f'<path d="M95 47C96 40 100 36 104 36C106 40 105 45 101 49Z" fill="{c["back"]}"/>'
          f'<ellipse cx="124" cy="81" rx="11.5" ry="12.5" fill="{c["snout"]}"/>'
          f'<ellipse cx="126.5" cy="81" rx="7.5" ry="9.5" fill="{c["snout_face"]}"/>'
          f'<ellipse cx="129.5" cy="74.5" rx="2.4" ry="1.5" fill="{c["light"]}"/><ellipse cx="124" cy="81" rx="1.7" ry="3" fill="{slot}"/>'
          f'<ellipse cx="130" cy="81" rx="1.7" ry="3" fill="{slot}"/>'
          f'<ellipse cx="108" cy="86" rx="6.5" ry="3.8" fill="{c["blush"]}" opacity=".35"/>')
    return s


EYES = {
    'open': f'<ellipse cx="104" cy="67" rx="3.6" ry="4.4" fill="{INK}"/><circle cx="105.3" cy="65.4" r="1.3" fill="#fff"/>',
    'closed': f'<path d="M99.5 67Q104 70.5 108.5 67" fill="none" stroke="{INK}" stroke-width="2.6" stroke-linecap="round"/>',
    'happy': f'<path d="M99.5 68.5Q104 62.5 108.5 68.5" fill="none" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>',
    'up': f'<ellipse cx="105" cy="65" rx="3.6" ry="4.4" fill="{INK}"/><circle cx="106.2" cy="63.3" r="1.3" fill="#fff"/>',
    'worried': (f'<ellipse cx="104" cy="68" rx="3.9" ry="4.8" fill="{INK}"/><circle cx="105.4" cy="66.2" r="1.4" fill="#fff"/>'
                f'<path d="M98.5 61.5L108 57.5" stroke="{INK}" stroke-width="2.2" stroke-linecap="round"/>'),
}
MOUTH = {
    'smile': f'<path d="M110 96Q115 99.5 120 96" fill="none" stroke="{TERRA}" stroke-width="2.2" stroke-linecap="round"/>',
    'big': f'<path d="M108 95Q115 101.5 122 95" fill="none" stroke="{TERRA}" stroke-width="2.4" stroke-linecap="round"/>',
    'flat': f'<path d="M111.5 96.5Q115 97.5 118.5 96.5" fill="none" stroke="{TERRA}" stroke-width="2.2" stroke-linecap="round"/>',
    'o': f'<ellipse cx="116" cy="97" rx="2.6" ry="3.2" fill="{TERRA}"/>',
}
COIN = ('<g><circle cx="78" cy="24" r="12.5" fill="#F2B544"/>'
        '<circle cx="78" cy="24" r="9" fill="none" stroke="#D9982B" stroke-width="2"/>'
        '<rect x="76.5" y="18" width="3" height="12" rx="1.5" fill="#D9982B"/>'
        '<path d="M70.5 20Q72 15.5 76.5 14.5" fill="none" stroke="#FFE3A3" stroke-width="2.2" stroke-linecap="round"/></g>')
EXTRAS = {
    'coin': COIN + '<path d="M60 13l4 4M96 13l-4 4" stroke="#E9C7B8" stroke-width="2" stroke-linecap="round"/>',
    'thought': ('<circle cx="128" cy="44" r="3.2" fill="#EAD6CA"/><circle cx="137" cy="33" r="4.4" fill="#EAD6CA"/>'
                '<circle cx="149" cy="20" r="6" fill="#EAD6CA"/>'),
    'zz': ('<path d="M126 40h9l-9 10h9" fill="none" stroke="#C98A75" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>'
           '<path d="M140 25h6l-6 7h6" fill="none" stroke="#C98A75" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'),
    'sweat': '<path d="M119 45C115.5 51 114.5 54.5 117.5 57C120.5 59.5 124.5 56.5 122.5 52.5Z" fill="#8CC8F2"/>',
}
MOODS = {
    'idle': ('open', 'smile', None),
    'happy': ('happy', 'big', 'coin'),
    'thinking': ('up', 'flat', 'thought'),
    'sleepy': ('closed', 'flat', 'zz'),
    'worried': ('worried', 'o', 'sweat'),
}

files = {}
for mood, (e, m, x) in MOODS.items():
    files[f'chanchi_{mood}.svg'] = svg(body() + EYES[e] + MOUTH[m] + (EXTRAS[x] if x else ''))
# Layers for animation (same viewBox): body, each eye state, each mouth, each extra.
files['layers/chanchi_body.svg'] = svg(body())
for k, v in EYES.items():
    files[f'layers/chanchi_eyes_{k}.svg'] = svg(v)
for k, v in MOUTH.items():
    files[f'layers/chanchi_mouth_{k}.svg'] = svg(v)
for k, v in EXTRAS.items():
    files[f'layers/chanchi_extra_{k}.svg'] = svg(v)

# App icon: adaptive foreground on a 108x108 canvas (safe zone = circle of 66 centred).
# Chanchi (160x140, content ~22..150 x 13..128) scaled to ~0.42 and centred.
ICON_C = dict(C)
fg_inner = (f'<g transform="translate(14.5 15) scale(0.5)">{body(ICON_C, slot="#8E3A21", shadow=False)}'
            f'{EYES["open"]}{MOUTH["smile"]}</g>')
files['icon/ic_foreground.svg'] = svg(fg_inner, '0 0 108 108')
files['icon/ic_background.svg'] = svg(f'<rect width="108" height="108" fill="{TERRA}"/>', '0 0 108 108')
mono = ('<mask id="m"><rect width="160" height="140" fill="#fff"/>'
        '<ellipse cx="104" cy="67" rx="3.6" ry="4.4" fill="#000"/>'
        '<rect x="66" y="46.5" width="24" height="5" rx="2.5" transform="rotate(-4 78 49)" fill="#000"/>'
        '<ellipse cx="124" cy="81" rx="1.7" ry="3" fill="#000"/><ellipse cx="130" cy="81" rx="1.7" ry="3" fill="#000"/></mask>'
        '<g mask="url(#m)" fill="#000">'
        '<path d="M76 52C76 40 82 32 90 32C94 38 94 47 89 54Z"/><rect x="50" y="104" width="15" height="19" rx="7"/>'
        '<rect x="94" y="104" width="15" height="19" rx="7"/><ellipse cx="80" cy="79" rx="47" ry="35"/>'
        '<rect x="60" y="106" width="16" height="19" rx="7"/><rect x="104" y="106" width="16" height="19" rx="7"/>'
        '<path d="M90 50C91 38 98 30 106 31C110 37 109 47 102 54Z"/><ellipse cx="124" cy="81" rx="11.5" ry="12.5"/></g>')
files['icon/ic_monochrome.svg'] = svg(f'<g transform="translate(14.5 15) scale(0.5)">{mono}</g>', '0 0 108 108')
files['icon/ic_legacy.svg'] = svg(f'<rect width="108" height="108" rx="24" fill="{TERRA}"/>{fg_inner}', '0 0 108 108')


# Onboarding scenes (260x150): a prop on the left, Chanchi on the right.
PROPS = {
    'local': ('<rect x="28" y="22" width="56" height="104" rx="12" fill="#fff" stroke="#EAD6CA" stroke-width="2"/>'
              '<rect x="35" y="32" width="42" height="80" rx="6" fill="#FFE3D3"/>'
              '<path d="M48 66v-6a8 8 0 0 1 16 0v6" fill="none" stroke="#BC4626" stroke-width="3.5" stroke-linecap="round"/>'
              '<rect x="44" y="65" width="24" height="19" rx="4.5" fill="#BC4626"/><circle cx="56" cy="74" r="2.6" fill="#FFE3D3"/>'),
    'receipt': ('<path d="M30 24h52v86l-6.5 5-6.5-5-6.5 5-6.5-5-6.5 5-6.5-5-6.5 5-6.5-5z" fill="#fff" stroke="#EAD6CA" stroke-width="2" stroke-linejoin="round"/>'
                '<rect x="38" y="36" width="30" height="4" rx="2" fill="#EAD6CA"/><rect x="38" y="48" width="36" height="4" rx="2" fill="#EAD6CA"/>'
                '<rect x="38" y="60" width="24" height="4" rx="2" fill="#EAD6CA"/><rect x="38" y="84" width="36" height="6" rx="3" fill="#BC4626"/>'
                '<path d="M92 16l2.2 5.3 5.3 2.2-5.3 2.2-2.2 5.3-2.2-5.3-5.3-2.2 5.3-2.2z" fill="#F2B544"/>'),
    'check': ('<circle cx="56" cy="72" r="34" fill="#E3F1E8"/><circle cx="56" cy="72" r="24" fill="#2A7A52"/>'
              '<path d="M44.5 72.5l8 8 15.5-16.5" fill="none" stroke="#fff" stroke-width="5.5" stroke-linecap="round" stroke-linejoin="round"/>'),
}
SCENE_MOOD = {'local': ('open', 'smile', None), 'receipt': ('happy', 'big', None), 'check': ('happy', 'big', 'coin')}
for k, prop in PROPS.items():
    e, m, x = SCENE_MOOD[k]
    pig = body() + EYES[e] + MOUTH[m] + (EXTRAS[x] if x else '')
    files[f'scenes/intro_{k}.svg'] = svg(prop + f'<g transform="translate(96 6)">{pig}</g>', '0 0 260 150')

for name, content in files.items():
    path = os.path.join(OUT, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(content)
print(len(files), 'files')
