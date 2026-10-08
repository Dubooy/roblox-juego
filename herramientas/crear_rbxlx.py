"""Genera MovimientoFPS.rbxlx (listo para abrir en Roblox Studio) a partir de src/.
Uso: python3 herramientas/crear_rbxlx.py"""
import itertools, os, glob
os.chdir(os.path.join(os.path.dirname(__file__), '..'))
r = itertools.count(1)
def src(p): return open(p, encoding='utf-8').read().replace(']]>', ']]]]><![CDATA[>')
def item(cls, name, kids='', extra=''):
    return f'<Item class="{cls}" referent="RBX{next(r)}"><Properties><string name="Name">{name}</string>{extra}</Properties>{kids}</Item>'
def script(path):
    base = os.path.basename(path)[:-4]
    cls = 'LocalScript' if base.endswith('.client') else 'Script' if base.endswith('.server') else 'ModuleScript'
    name = base.split('.')[0]
    return item(cls, name, extra=f'<ProtectedString name="Source"><![CDATA[{src(path)}]]></ProtectedString>')
def todos(d): return ''.join(script(p) for p in sorted(glob.glob(f'src/{d}/*.lua')))
x = '<roblox version="4">' + item('Workspace', 'Workspace')
# Iluminación con sombras suaves (no se puede cambiar desde un script)
x += item('Lighting', 'Lighting', extra='<token name="Technology">3</token>')
x += item('ReplicatedStorage', 'ReplicatedStorage', item('Folder', 'Shared', todos('shared')))
x += item('ServerScriptService', 'ServerScriptService', todos('server'))
x += item('StarterPlayer', 'StarterPlayer', item('StarterPlayerScripts', 'StarterPlayerScripts', todos('client')), '<token name="CameraMode">1</token>')
open('MovimientoFPS.rbxlx', 'w', encoding='utf-8').write(x + '</roblox>')
print('MovimientoFPS.rbxlx creado')
