# MMRL Reference Modules — GUI Patterns

> Fetch live si le skill est déclenché avec "module récent" ou "comme X" :
> web_search "site:github.com MMRLApp OR Magisk-Modules-Alt-Repo <topic> module webroot"

## Patterns GUI documentés

### bindhosts (DNS/hosts blocker)
- **Tabs** : Status · Whitelist · Blocklist · Logs
- **Pattern clé** : toggle switch par règle, recherche en temps réel dans une liste
- **Référence** : https://github.com/bindhosts/bindhosts

### AppNuker (app disabler/freezer)
- **Tabs** : Apps · Frozen · Logs
- **Pattern clé** : liste d'apps avec icônes (ksu.getPackagesIcons), toggle freeze
- **Référence** : https://github.com/MMRLApp/AppNuker
- **Trick icônes** : `ksu.getPackagesInfo(JSON.stringify(pkgs))` → appLabel + uid

### Zygisk-Assistant
- **Pattern clé** : liste de règles avec bouton + , confirmation avant suppression
- **Référence** : https://github.com/snake-4/Zygisk-Assistant

## Patterns UI réutilisables

### App picker avec icônes (AppNuker pattern)
```javascript
async function loadAppList() {
  const raw = ksu.listUserPackages();
  const pkgs = JSON.parse(raw);
  const info = JSON.parse(ksu.getPackagesInfo(JSON.stringify(pkgs)));
  return info.map(p => ({ pkg: p.packageName, label: p.appLabel, uid: p.uid }));
}
```

### Toggle switch
```html
<label class="toggle">
  <input type="checkbox" onchange="onToggle(this)">
  <span class="slider"></span>
</label>
```
```css
.toggle { position:relative; display:inline-block; width:44px; height:24px; }
.toggle input { opacity:0; width:0; height:0; }
.slider { position:absolute; inset:0; background:var(--border); border-radius:24px;
          transition:.3s; cursor:pointer; }
.slider::before { content:''; position:absolute; width:18px; height:18px; left:3px; top:3px;
                  background:#fff; border-radius:50%; transition:.3s; }
input:checked + .slider { background:var(--accent); }
input:checked + .slider::before { transform:translateX(20px); }
```

### Search filter sur liste
```javascript
document.getElementById('search').addEventListener('input', function() {
  const q = this.value.toLowerCase();
  document.querySelectorAll('.list-item').forEach(el => {
    el.style.display = el.dataset.pkg.includes(q) ? '' : 'none';
  });
});
```

### Progress bar partition
```html
<div class="prog-bar">
  <div class="prog-fill ok" id="prog-internal" style="width:0%"></div>
</div>
```
```css
.prog-bar { height:4px; background:var(--border); border-radius:2px; margin:6px 0; }
.prog-fill { height:100%; border-radius:2px; transition:width .5s; }
.prog-fill.ok   { background:var(--accent); }
.prog-fill.warn { background:var(--warn); }
.prog-fill.crit { background:var(--err); }
```
