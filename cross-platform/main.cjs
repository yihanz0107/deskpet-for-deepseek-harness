const { app, BrowserWindow, ipcMain, screen, shell } = require('electron')
const http = require('node:http')
const fs = require('node:fs')
const path = require('node:path')

const HOST = '127.0.0.1'
const PORT = 3081
const BASE_WIDTH = 250
const BASE_HEIGHT = 310
const VALID_ID = /^[a-z0-9][a-z0-9-]{0,120}$/
const DEFAULT_ZH = ['主人～坐久了，站起来休息休息吧', '主人～喝口水，我们再继续', '今天也要记得照顾好自己哦', '我在这里陪你一起完成任务']
const DEFAULT_EN = ["You've been sitting for a while—time to stand up and stretch!", "Take a sip of water, then let's keep going.", 'Remember to take good care of yourself today.', "I'm right here, working through this task with you."]

let win
let server
let dataRoot
let petsRoot
let settingsFile
let settings
let petdexCache
const catalogCache = new Map()

function readJSON(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')) } catch { return fallback }
}

function writeJSON(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true })
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 })
}

function initialSettings() {
  return { scale: 0.5, visible: true, status: 'idle', label: '', locale: app.getLocale().toLowerCase().startsWith('en') ? 'en' : 'zh-CN', petId: 'bongocat--ayangweb', phrases: [] }
}

function seedPets() {
  fs.mkdirSync(petsRoot, { recursive: true })
  const bundled = path.join(__dirname, 'BundledPets')
  if (!fs.existsSync(bundled)) return
  for (const id of fs.readdirSync(bundled)) {
    if (!VALID_ID.test(id)) continue
    const source = path.join(bundled, id)
    const destination = path.join(petsRoot, id)
    if (!fs.existsSync(destination)) fs.cpSync(source, destination, { recursive: true })
  }
}

function manifestFor(id) {
  if (!VALID_ID.test(id)) return null
  if (id === 'bongocat--ayangweb') {
    const bundledSheet = path.join(__dirname, 'bongocat-spritesheet.png')
    if (!fs.existsSync(path.join(petsRoot, id, 'pet.json')) && fs.existsSync(bundledSheet)) {
      return { id, displayName: 'BongoCat', description: 'BongoCat desktop companion', source: 'bongocat', sourcePetID: 'ayangweb/bongocat', spriteVersionNumber: 2, sheet: bundledSheet }
    }
  }
  const dir = path.join(petsRoot, id)
  const manifest = readJSON(path.join(dir, 'pet.json'), null)
  const sheet = path.join(dir, manifest?.spritesheetPath || 'spritesheet.webp')
  return manifest && fs.existsSync(sheet) ? { ...manifest, id, sheet } : null
}

function allPets() {
  const pets = fs.existsSync(petsRoot) ? fs.readdirSync(petsRoot).sort().flatMap(id => {
    const pet = manifestFor(id)
    if (!pet) return []
    return [{ id, displayName: pet.displayName || id, description: pet.description || '', spriteVersionNumber: pet.spriteVersionNumber || 1, selected: id === settings.petId, builtIn: false, source: pet.source || '', sourcePetID: pet.sourcePetID || '', previewURL: pet.previewURL || '' }]
  }) : []
  if (!pets.some(pet => pet.id === 'bongocat--ayangweb') && manifestFor('bongocat--ayangweb')) {
    pets.unshift({ id: 'bongocat--ayangweb', displayName: 'BongoCat', description: 'BongoCat desktop companion', spriteVersionNumber: 2, selected: settings.petId === 'bongocat--ayangweb', builtIn: true, source: 'bongocat', sourcePetID: 'ayangweb/bongocat', previewURL: '' })
  }
  return pets
}

function currentPet() {
  return manifestFor(settings.petId) || manifestFor('bongocat--ayangweb') || allPets().map(p => manifestFor(p.id)).find(Boolean)
}

function saveSettings() {
  writeJSON(settingsFile, settings)
}

function windowSize(scale = settings.scale) {
  return { width: Math.round(BASE_WIDTH * scale), height: Math.round(BASE_HEIGHT * scale) }
}

function rendererState(extra = {}) {
  const pet = currentPet()
  return { ...settings, phrases: effectivePhrases(), sheet: pet ? `file://${pet.sheet.replace(/\\/g, '/')}` : '', ...extra }
}

function effectivePhrases() {
  return settings.phrases?.length ? settings.phrases : (settings.locale.startsWith('en') ? DEFAULT_EN : DEFAULT_ZH)
}

function sendState(extra) {
  if (win && !win.isDestroyed()) win.webContents.send('pet-state', rendererState(extra))
}

function resizeWindow(scale) {
  const old = win.getBounds()
  const next = windowSize(scale)
  win.setBounds({ x: Math.round(old.x + (old.width - next.width) / 2), y: Math.round(old.y + old.height - next.height), ...next })
}

function createWindow() {
  const size = windowSize()
  const area = screen.getPrimaryDisplay().workArea
  const saved = settings.position || {}
  win = new BrowserWindow({
    ...size,
    x: Number.isFinite(saved.x) ? saved.x : area.x + area.width - size.width - 20,
    y: Number.isFinite(saved.y) ? saved.y : area.y + area.height - size.height - 20,
    transparent: true,
    frame: false,
    resizable: false,
    hasShadow: false,
    alwaysOnTop: true,
    skipTaskbar: true,
    show: false,
    webPreferences: { contextIsolation: false, nodeIntegration: true }
  })
  win.setAlwaysOnTop(true, 'floating')
  win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })
  win.loadFile(path.join(__dirname, 'pet.html'))
  win.once('ready-to-show', () => { if (settings.visible) win.showInactive(); sendState() })
  win.on('moved', () => { const { x, y } = win.getBounds(); settings.position = { x, y }; saveSettings() })
  win.on('closed', () => { win = null })
}

ipcMain.on('drag-start', (_, point) => {
  if (!win) return
  const start = screen.getCursorScreenPoint()
  const bounds = win.getBounds()
  const move = setInterval(() => {
    if (!win || win.isDestroyed()) return clearInterval(move)
    const cursor = screen.getCursorScreenPoint()
    win.setPosition(bounds.x + cursor.x - start.x, bounds.y + cursor.y - start.y)
  }, 16)
  ipcMain.once('drag-end', () => clearInterval(move))
})
ipcMain.on('open-harness', () => shell.openExternal('http://127.0.0.1:3080'))

async function getBuffer(url, maxBytes = 20_000_000, attempts = 3) {
  for (let attempt = 0; attempt < attempts; attempt++) {
    try {
      const response = await fetch(url, { headers: { 'User-Agent': 'DeepSSPet/1.0' } })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const buffer = Buffer.from(await response.arrayBuffer())
      if (!buffer.length || buffer.length > maxBytes) throw new Error('Invalid download size')
      return buffer
    } catch (error) {
      if (attempt === attempts - 1) throw error
      await new Promise(resolve => setTimeout(resolve, 250 * (attempt + 1)))
    }
  }
}

async function getJSON(url, maxBytes = 4_000_000) {
  return JSON.parse((await getBuffer(url, maxBytes)).toString('utf8'))
}

async function petdexEntries() {
  if (petdexCache) return petdexCache
  const doc = await getJSON('https://assets.petdex.dev/manifests/petdex-v2.json')
  const index = Object.fromEntries(doc.fields.map((field, i) => [field, i]))
  petdexCache = doc.pets.flatMap(row => {
    const id = row[index.slug]
    if (!VALID_ID.test(id)) return []
    return [{ id, displayName: row[index.displayName] || id, kind: row[index.kind] || '', spritesheetPath: row[index.spritesheet], petJsonPath: row[index.petJson], spriteVersionNumber: row[index.spriteVersionNumber] || 1, previewURL: `https://assets.petdex.dev/pets/${id}/preview.webp` }]
  })
  return petdexCache
}

async function sourceEntries(source) {
  if (catalogCache.has(source)) return catalogCache.get(source)
  let entries
  if (source === 'agentbro') {
    const doc = await getJSON('https://api.agentbro.net/api/manifest')
    entries = (doc.pets || []).filter(p => (p.status || 'approved') === 'approved' && VALID_ID.test(p.slug)).map(p => ({ id: p.slug, displayName: p.displayName || p.slug, description: p.description || '', kind: p.kind || '', previewURL: p.spritesheetUrl, spritesheetURL: p.spritesheetUrl, manifestURL: p.petJsonUrl || '' }))
  } else if (source === 'openpets') {
    const pages = await Promise.all(Array.from({ length: 13 }, (_, page) => getJSON(`https://openpets.dev/pets/catalog.v3/page-${String(page).padStart(3, '0')}.json`).catch(() => ({ pets: [] }))))
    entries = pages.flatMap(doc => doc.pets || []).filter(p => VALID_ID.test(p.id) && p.spritesheet).map(p => ({ id: p.id, displayName: p.displayName || p.id, description: p.description || '', kind: p.subcategory || p.category || '', previewURL: p.thumbnail || p.spritesheet, spritesheetURL: p.spritesheet }))
  } else if (source === 'codex-anime-pets') {
    const rows = await getJSON('https://api.github.com/repos/chenxin-dlut/codex-anime-pets/contents/pets?ref=main')
    entries = rows.filter(row => row.type === 'dir' && VALID_ID.test(row.name)).map(row => ({ id: row.name, displayName: row.name.split('-').map(v => v[0].toUpperCase() + v.slice(1)).join(' '), description: 'Anime pet from Codex Anime Pets', previewURL: `https://raw.githubusercontent.com/chenxin-dlut/codex-anime-pets/main/assets/previews/${row.name}.png`, spritesheetURL: `https://raw.githubusercontent.com/chenxin-dlut/codex-anime-pets/main/pets/${row.name}/spritesheet.webp`, manifestURL: `https://raw.githubusercontent.com/chenxin-dlut/codex-anime-pets/main/pets/${row.name}/pet.json` }))
  } else if (source === 'spriteyard') {
    const html = (await getBuffer('https://www.spriteyard.com/')).toString('utf8')
    const regex = /\\\"creator\\\":\\\".*?\\\",\\\"description\\\":\\\"(.*?)\\\".*?\\\"galleryPreviewUrl\\\":\\\"(.*?)\\\",\\\"name\\\":\\\"(.*?)\\\".*?\\\"previewUrl\\\":\\\"(.*?)\\\".*?\\\"slug\\\":\\\"([a-z0-9-]+)\\\"/g
    entries = [...html.matchAll(regex)].map(m => ({ id: m[5], displayName: m[3], description: m[1], previewURL: m[2].replaceAll('\\\\', ''), spritesheetURL: m[4].replaceAll('\\\\', '') }))
  } else throw new Error('Unsupported catalog source')
  catalogCache.set(source, entries)
  return entries
}

function paged(entries, body) {
  const page = Math.max(1, Math.min(10000, Number(body.page) || 1))
  const pageSize = Math.max(1, Math.min(48, Number(body.pageSize) || 18))
  const query = String(body.query || '').trim().toLowerCase()
  const filtered = query ? entries.filter(p => [p.id, p.displayName, p.description, p.kind].some(v => String(v || '').toLowerCase().includes(query))) : entries
  return { pets: filtered.slice((page - 1) * pageSize, page * pageSize), page, pageSize, total: filtered.length }
}

async function catalog(body) {
  if (body.source === 'codex-pets') {
    const query = new URLSearchParams({ page: body.page || 1, pageSize: Math.min(48, body.pageSize || 18), sort: 'popular' })
    if (body.query) query.set('q', String(body.query).slice(0, 80))
    return getJSON(`https://codex-pets.net/api/pets?${query}`)
  }
  if (body.source === 'petdex') {
    const entries = await petdexEntries()
    return paged(entries.map(p => ({ ...p, description: 'Desktop pet from PetDex' })), body)
  }
  return paged(await sourceEntries(body.source), body)
}

async function installPet(source, remoteID) {
  if (!VALID_ID.test(remoteID)) throw new Error('Invalid pet identifier')
  let localID
  let manifest
  let sheetURL
  if (source === 'awesome-codex-pet' || source === 'awesome') {
    localID = remoteID
    const base = `https://raw.githubusercontent.com/legeling/awesome-codex-pet/main/pets/${remoteID}`
    manifest = await getJSON(`${base}/pet.json`, 128000)
    sheetURL = `${base}/spritesheet.webp`
  } else if (source === 'codex-pets') {
    const detail = await getJSON(`https://codex-pets.net/api/pets/${remoteID}`)
    const pet = detail.pet
    if (!pet?.spritesheetUrl) throw new Error('Pet download failed')
    localID = `codex-pets--${remoteID}`
    manifest = { displayName: pet.displayName || remoteID, description: pet.description || '', previewURL: pet.posterUrl || pet.previewUrl || '' }
    sheetURL = pet.spritesheetUrl
  } else if (source === 'petdex') {
    const entry = (await petdexEntries()).find(p => p.id === remoteID)
    if (!entry) throw new Error('Pet not found')
    localID = `petdex--${remoteID}`
    manifest = await getJSON(`https://assets.petdex.dev/${entry.petJsonPath}`, 128000).catch(() => ({ displayName: entry.displayName, description: 'Desktop pet from PetDex' }))
    sheetURL = `https://assets.petdex.dev/${entry.spritesheetPath}`
    manifest.previewURL = entry.previewURL
  } else {
    const entry = (await sourceEntries(source)).find(p => p.id === remoteID)
    if (!entry?.spritesheetURL) throw new Error('Pet not found')
    localID = `${source}--${remoteID}`
    manifest = entry.manifestURL ? await getJSON(entry.manifestURL, 128000).catch(() => ({})) : {}
    manifest = { displayName: entry.displayName || remoteID, description: entry.description || '', ...manifest, previewURL: entry.previewURL || entry.spritesheetURL }
    sheetURL = entry.spritesheetURL
  }
  if (!VALID_ID.test(localID)) throw new Error('Invalid local pet identifier')
  const sheet = await getBuffer(sheetURL)
  const dir = path.join(petsRoot, localID)
  fs.mkdirSync(dir, { recursive: true })
  const normalized = { ...manifest, id: localID, source, sourcePetID: remoteID, spritesheetPath: 'spritesheet.webp' }
  fs.writeFileSync(path.join(dir, 'spritesheet.webp'), sheet)
  writeJSON(path.join(dir, 'pet.json'), normalized)
  settings.petId = localID
  saveSettings()
  sendState()
}

function petsSnapshot() {
  return { ok: true, selectedPetId: settings.petId, pets: allPets(), scale: settings.scale, visible: settings.visible }
}

function applyControl(body) {
  if (typeof body.locale === 'string') settings.locale = body.locale
  if (typeof body.status === 'string') settings.status = body.status
  if (typeof body.label === 'string') settings.label = body.label.slice(0, 60)
  if (typeof body.visible === 'boolean') { settings.visible = body.visible; body.visible ? win?.showInactive() : win?.hide() }
  if (Number.isFinite(body.scale)) {
    const scale = Math.max(0.2, Math.min(1.5, Number(body.scale)))
    if (scale !== settings.scale) { settings.scale = scale; resizeWindow(scale) }
  }
  saveSettings()
  sendState()
}

async function route(method, pathname, body, query) {
  if (method === 'GET' && pathname === '/state') return { ok: true, ...settings }
  if (method === 'GET' && pathname === '/pets') return petsSnapshot()
  if (method === 'GET' && pathname === '/phrases') return { ok: true, phrases: effectivePhrases() }
  if (method === 'POST' && pathname === '/control') { applyControl(body); return { ok: true, ...settings } }
  if (method === 'POST' && pathname === '/phrases') { settings.phrases = Array.isArray(body.phrases) ? body.phrases.map(v => String(v).trim()).filter(Boolean).slice(0, 30) : []; saveSettings(); sendState(); return { ok: true, phrases: effectivePhrases() } }
  if (method === 'POST' && pathname === '/select') { if (!manifestFor(body.id)) throw new Error('Installed pet not found'); settings.petId = body.id; saveSettings(); sendState(); return petsSnapshot() }
  if (method === 'POST' && pathname === '/delete') { if (body.id === 'bongocat--ayangweb') throw new Error('The default pet cannot be deleted'); fs.rmSync(path.join(petsRoot, body.id), { recursive: true, force: true }); if (settings.petId === body.id) settings.petId = 'bongocat--ayangweb'; saveSettings(); sendState(); return petsSnapshot() }
  if (method === 'POST' && pathname === '/catalog') return { ok: true, ...(await catalog(body)) }
  if (method === 'POST' && pathname === '/install') { await installPet(body.source || 'awesome-codex-pet', body.id || body.slug); return petsSnapshot() }
  if (method === 'POST' && pathname === '/focus') { await shell.openExternal('http://127.0.0.1:3080'); return { ok: true, reused: true } }
  if (method === 'POST' && pathname === '/quit') { app.quit(); return { ok: true } }
  if (method === 'GET' && pathname === '/preview') {
    const source = query.get('source'); const id = query.get('id')
    const url = source === 'petdex' ? `https://assets.petdex.dev/pets/${id}/preview.webp` : `https://codexpet.top/assets/previews/${id}/thumbnail.webp`
    return { __binary: await getBuffer(url, 2_000_000), contentType: 'image/webp' }
  }
  return { ok: true, ...settings }
}

function startServer() {
  server = http.createServer(async (req, res) => {
    res.setHeader('Access-Control-Allow-Origin', 'http://127.0.0.1:3080')
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type')
    if (req.method === 'OPTIONS') { res.writeHead(204); return res.end() }
    try {
      const chunks = []
      for await (const chunk of req) chunks.push(chunk)
      const body = chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {}
      const url = new URL(req.url, `http://${HOST}:${PORT}`)
      const result = await route(req.method, url.pathname, body, url.searchParams)
      if (result.__binary) { res.writeHead(200, { 'Content-Type': result.contentType, 'Content-Length': result.__binary.length }); return res.end(result.__binary) }
      const output = Buffer.from(JSON.stringify(result))
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Content-Length': output.length })
      res.end(output)
    } catch (error) {
      const output = Buffer.from(JSON.stringify({ ok: false, error: error.message || String(error) }))
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Content-Length': output.length })
      res.end(output)
    }
  })
  server.on('error', error => { if (error.code === 'EADDRINUSE') app.quit(); else throw error })
  server.listen(PORT, HOST)
}

app.whenReady().then(() => {
  dataRoot = app.getPath('userData')
  petsRoot = path.join(dataRoot, 'pets')
  settingsFile = path.join(dataRoot, 'settings.json')
  settings = { ...initialSettings(), ...readJSON(settingsFile, {}) }
  seedPets()
  if (!manifestFor(settings.petId)) settings.petId = 'bongocat--ayangweb'
  createWindow()
  startServer()
})

app.on('window-all-closed', event => event.preventDefault())
app.on('before-quit', () => server?.close())
