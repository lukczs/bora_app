NIGHT='#0F172A'; GREEN='#22C55E'; MINT='#BDF5E1'
def mark(arc=MINT, arrow=GREEN):
    # Eixos de Brasília: o arco é o Eixo Rodoviário, a flecha é o Eixo Monumental
    return f'''<path d="M17 40 Q50 72 83 40" fill="none" stroke="{arc}" stroke-width="8" stroke-linecap="round"/>
<path d="M50 14 L50 72" fill="none" stroke="{arrow}" stroke-width="6" stroke-linecap="round"/>
<path d="M39 70 L61 70 L50 88 Z" fill="{arrow}" stroke="{arrow}" stroke-width="2" stroke-linejoin="round"/>
<path d="M41 11 L50 19 L59 11 M41 19 L50 27 L59 19" fill="none" stroke="{arrow}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>'''
def svg(size=100, tile=True, pad=0.0, radius=22):
    inner = mark()
    s = 100*(1-2*pad); o = 100*pad
    bg = f'<rect width="100" height="100" rx="{radius}" fill="{NIGHT}"/>' if tile else ''
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 100 100">{bg}<g transform="translate({o} {o}) scale({s/100})">{inner}</g></svg>'
if __name__ == '__main__':
    open('/home/claude/logo_out/bora_icon.svg','w').write(svg(1024, True, .12))
    open('/home/claude/logo_out/bora_mark.svg','w').write(svg(1024, False, 0))
    open('/home/claude/logo_out/bora_foreground.svg','w').write(svg(1024, False, .25))  # Android adaptativo: área segura
