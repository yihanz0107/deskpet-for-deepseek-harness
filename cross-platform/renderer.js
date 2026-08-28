const { ipcRenderer } = require('electron')
const canvas = document.querySelector('#pet')
const bubble = document.querySelector('#bubble')
const context = canvas.getContext('2d')
const frameCounts = [6, 8, 8, 4, 5, 8, 6, 6, 6]
const rows = { idle: 0, waving: 3, jumping: 4, failed: 5, waiting: 6, running: 7, review: 8 }
let state = { status: 'idle', label: '', phrases: [] }
let image = new Image()
let frame = 0
let interaction = null
let interactionTimer
let dragging = false
let moved = false
let downPoint
let lastSheet = ''

function showBubble(text, duration = 5000) {
  bubble.textContent = text
  bubble.classList.toggle('show', Boolean(text))
  clearTimeout(showBubble.timer)
  if (text && duration) showBubble.timer = setTimeout(() => bubble.classList.remove('show'), duration)
}

function resize() {
  const ratio = devicePixelRatio || 1
  canvas.width = Math.round(innerWidth * ratio)
  canvas.height = Math.round(innerHeight * ratio)
}

function draw() {
  if (!image.complete || !image.naturalWidth) return
  const row = rows[interaction || state.status] ?? 0
  const sourceWidth = image.naturalWidth / 8
  const sourceHeight = 208
  const index = frame % frameCounts[row]
  context.clearRect(0, 0, canvas.width, canvas.height)
  context.imageSmoothingEnabled = false
  const margin = Math.max(2, canvas.width * .04)
  const top = bubble.classList.contains('show') ? Math.min(canvas.height * .28, 48 * devicePixelRatio) : 2
  const availableWidth = canvas.width - margin * 2
  const availableHeight = canvas.height - top - margin
  const width = Math.min(availableWidth, availableHeight * 192 / 208)
  const height = width * 208 / 192
  context.drawImage(image, index * sourceWidth, row * sourceHeight, sourceWidth, sourceHeight, (canvas.width - width) / 2, top + (availableHeight - height) / 2, width, height)
}

function temporaryAction(action, duration = 1300) {
  interaction = action
  frame = 0
  clearTimeout(interactionTimer)
  interactionTimer = setTimeout(() => { interaction = null; frame = 0 }, duration)
}

ipcRenderer.on('pet-state', (_, next) => {
  state = next
  if (next.sheet && next.sheet !== lastSheet) { lastSheet = next.sheet; image = new Image(); image.onload = draw; image.src = next.sheet }
  if ((next.status === 'running' || next.status === 'waiting') && next.label) showBubble(next.label, 0)
  else if (!interaction) bubble.classList.remove('show')
})

document.body.addEventListener('mouseenter', () => { if (!dragging) temporaryAction('waving', 1100) })
document.body.addEventListener('mousedown', event => {
  if (event.button !== 0) return
  downPoint = { x: event.screenX, y: event.screenY, time: Date.now() }
  dragging = true; moved = false; document.body.classList.add('dragging'); ipcRenderer.send('drag-start', downPoint)
})
window.addEventListener('mousemove', event => { if (dragging && Math.hypot(event.screenX - downPoint.x, event.screenY - downPoint.y) > 3) moved = true })
window.addEventListener('mouseup', () => {
  if (!dragging) return
  dragging = false; document.body.classList.remove('dragging'); ipcRenderer.send('drag-end')
  if (!moved) {
    const actions = ['waving', 'jumping', 'failed', 'waiting', 'running', 'review']
    temporaryAction(actions[Math.floor(Math.random() * actions.length)])
    if (state.phrases?.length) showBubble(state.phrases[Math.floor(Math.random() * state.phrases.length)])
  }
})
document.body.addEventListener('dblclick', () => ipcRenderer.send('open-harness'))
window.addEventListener('resize', resize)
resize()
setInterval(() => { frame++; draw() }, 130)
