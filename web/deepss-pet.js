(() => {
  const endpoint = 'http://127.0.0.1:3081'
  const harnessLocale = () => (document.documentElement.lang || navigator.language || 'zh-CN')
  const tr = (chinese, english) => /^en\b/i.test(harnessLocale()) ? english : chinese
  const catalogURL = 'https://raw.githubusercontent.com/legeling/awesome-codex-pet/main/pets.json'
  const catalogPageSize = 18
  let mode = localStorage.getItem('deepss-pet-mode') || 'auto'
  let lastPayload = ''
  let syncTimer
  let scaleTimer
  let lastAutoStatus = 'idle'
  let reviewUntil = 0
  let awesomeCatalog = []
  let awesomeVisibleCount = catalogPageSize
  let awesomeQuery = ''
  let codexPetsCatalog = []
  let codexPetsPage = 1
  let codexPetsTotal = 0
  let codexPetsQuery = ''
  let petdexCatalog = []
  let petdexPage = 1
  let petdexTotal = 0
  let petdexQuery = ''
  const extraSourceDefs = [
    { id: 'spriteyard', label: 'SpriteYard' },
    { id: 'agentbro', label: 'AgentBro' },
    { id: 'openpets', label: 'OpenPets' },
    { id: 'codex-anime-pets', label: 'Anime Pets' },
  ]
  const extraCatalogs = Object.fromEntries(extraSourceDefs.map(source => [source.id, { pets: [], page: 1, total: 0, query: '' }]))
  let catalogSearchTimer
  let installed = new Map()
  let selectedPetID = ''
  let previewObserver
  let catalogMoreObserver
  let catalogLoadingMore = false
  let catalogSourceCursor = 0

  const api = async (path, payload) => {
    const response = await fetch(`${endpoint}${path}`, {
      method: payload === undefined ? 'GET' : 'POST',
      headers: payload === undefined ? undefined : { 'Content-Type': 'application/json' },
      body: payload === undefined ? undefined : JSON.stringify(payload),
    })
    if (!response.ok) throw new Error(`HTTP ${response.status}`)
    const data = await response.json()
    if (data.ok === false) throw new Error(data.error || tr('操作失败', 'Operation failed'))
    return data
  }

  const setHealth = (text, connected) => document.querySelectorAll('[data-deepss-pet-health]').forEach(element => {
    element.textContent = text
    element.dataset.connected = String(connected)
  })

  const visibleTextExists = (values) => [...document.querySelectorAll('button, [role="status"], [role="alert"]')]
    .some(element => element.getClientRects().length > 0 && values.some(value => (element.textContent || '').includes(value)))

  const currentTaskTitle = () => {
    const title = document.title.split(/\s+—\s+/)[0]?.trim() || ''
    if (title && !/^(DeepSeek Harness|DSH Local Build)$/i.test(title)) return title
    const active = document.querySelector('[role="treeitem"][aria-current="true"], [role="treeitem"][data-selected="true"]')
    const text = active?.textContent?.replace(/\s+/g, ' ').trim() || ''
    return text.length <= 80 ? text : text.slice(0, 80)
  }

  const detect = () => {
    const stop = document.querySelector('button[aria-label="停止生成"], button[aria-label="Stop generating"]')
    const jobButton = [...document.querySelectorAll('button[aria-label]')].find(button =>
      /后台任务运行中|background jobs? running/i.test(button.getAttribute('aria-label') || ''))
    const match = jobButton?.getAttribute('aria-label')?.match(/\d+/)
    const count = match ? Number(match[0]) : 0
    if (visibleTextExists(['本轮失败', 'This turn failed', '命令失败', 'Command failed'])) {
      lastAutoStatus = 'failed'
      return { status: 'failed', label: '', count }
    }
    if (visibleTextExists(['等待审批', 'Waiting for approval', '等待回答'])) {
      lastAutoStatus = 'waiting'
      return { status: 'waiting', label: currentTaskTitle() || tr('等待你确认的任务', 'Waiting for your confirmation'), count }
    }
    if (stop || count > 0) {
      lastAutoStatus = 'running'
      return { status: 'running', label: currentTaskTitle() || (count > 0 ? tr(`DeepSeek 正在执行 ${count} 个任务`, `DeepSeek is running ${count} task(s)`) : tr('DeepSeek Harness 正在思考', 'DeepSeek Harness is thinking')), count }
    }
    if (lastAutoStatus === 'running') reviewUntil = Date.now() + 2000
    if (Date.now() < reviewUntil) {
      lastAutoStatus = 'review'
      return { status: 'review', label: '', count: 0 }
    }
    lastAutoStatus = 'idle'
    return { status: 'idle', label: '', count: 0 }
  }

  const sync = async () => {
    if (mode === 'auto' && document.visibilityState !== 'visible') return
    const state = { ...(mode === 'auto' ? detect() : { status: mode, label: '' }), locale: harnessLocale() }
    const payload = JSON.stringify(state)
    if (payload === lastPayload) return
    lastPayload = payload
    try {
      await api('/control', state)
      setHealth(tr('已连接', 'Connected'), true)
    } catch {
      lastPayload = ''
      setHealth(tr('桌宠未启动', 'DeskPet is not running'), false)
    }
  }

  const installStyles = () => {
    if (document.querySelector('#deepss-pet-settings-style')) return
    const style = document.createElement('style')
    style.id = 'deepss-pet-settings-style'
    style.textContent = `
      #deepss-pet-settings-page{box-sizing:border-box;width:100%;padding:4px 2px 28px;color:inherit}
      .deepss-pet-head{display:flex;align-items:flex-start;justify-content:space-between;gap:20px;margin-bottom:22px}
      .deepss-pet-head h2{font-size:20px;margin:0 0 6px}.deepss-pet-head p{margin:0;opacity:.62;font-size:13px}
      .deepss-pet-primary,.deepss-pet-button{font:inherit;color:inherit;border:1px solid color-mix(in srgb,currentColor 16%,transparent);border-radius:9px;padding:7px 11px;cursor:pointer;background:color-mix(in srgb,currentColor 7%,transparent)}
      .deepss-pet-primary{color:white;background:#3f6fec;border-color:#3f6fec}.deepss-pet-button:hover{background:color-mix(in srgb,currentColor 12%,transparent)}
      .deepss-pet-controls{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:26px}
      .deepss-pet-setting-card{border:1px solid color-mix(in srgb,currentColor 12%,transparent);border-radius:12px;padding:14px;background:color-mix(in srgb,currentColor 3%,transparent)}
      .deepss-pet-setting-card label{display:block;font-size:13px;font-weight:600;margin-bottom:9px}.deepss-pet-setting-card small{opacity:.58}
      .deepss-pet-setting-card select{width:100%;font:inherit;color:inherit;background:transparent;border:1px solid color-mix(in srgb,currentColor 18%,transparent);border-radius:8px;padding:7px}
      .deepss-pet-setting-card-wide{grid-column:1/-1}.deepss-pet-setting-card textarea{box-sizing:border-box;width:100%;min-height:126px;resize:vertical;font:inherit;line-height:1.55;color:inherit;background:transparent;border:1px solid color-mix(in srgb,currentColor 18%,transparent);border-radius:8px;padding:9px 10px}.deepss-pet-phrase-foot{display:flex;align-items:center;justify-content:space-between;gap:10px;margin-top:9px}.deepss-pet-phrase-foot small{font-size:12px}
      .deepss-pet-range-line{display:flex;align-items:center;gap:10px}.deepss-pet-range-line input{flex:1}.deepss-pet-range-line output{width:36px;font-variant-numeric:tabular-nums}
      .deepss-pet-inline-buttons{display:flex;align-items:center;gap:8px}.deepss-pet-inline-buttons [data-deepss-pet-health]{margin-left:auto;font-size:12px;color:#36a15d}.deepss-pet-inline-buttons [data-connected="false"]{color:#d85c5c}
      .deepss-pet-section-title{display:flex;align-items:center;justify-content:space-between;margin:0 0 12px}.deepss-pet-section-title h3{margin:0;font-size:15px}
      .deepss-pet-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:12px}
      .deepss-pet-card{min-width:0;border:1px solid color-mix(in srgb,currentColor 12%,transparent);border-radius:13px;padding:10px;background:color-mix(in srgb,currentColor 3%,transparent)}
      .deepss-pet-card.selected{border-color:#5c82ed;box-shadow:0 0 0 1px #5c82ed55}.deepss-pet-preview{width:100%;height:118px;object-fit:contain;border-radius:9px;background:color-mix(in srgb,currentColor 5%,transparent);image-rendering:auto;visibility:hidden}.deepss-pet-preview.loaded{visibility:visible}
      .deepss-pet-card h4{margin:9px 0 3px;font-size:14px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.deepss-pet-card p{height:34px;margin:0 0 9px;font-size:12px;line-height:17px;opacity:.58;overflow:hidden}
      .deepss-pet-card-foot{display:flex;align-items:center;justify-content:space-between;gap:8px}.deepss-pet-card-foot>span{font-size:11px;opacity:.55;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.deepss-pet-card-actions{display:flex;gap:6px;flex:none}.deepss-pet-card-foot button{flex:none}.deepss-pet-delete{color:#d64c4c;border-color:#d64c4c66}
      #deepss-pet-store{position:fixed;inset:0;z-index:2147483647;display:none;flex-direction:column;color:#ececf1;background:#101014f7;backdrop-filter:blur(24px)}
      #deepss-pet-store.open{display:flex}.deepss-pet-store-head{display:flex;align-items:center;gap:14px;padding:18px 24px;border-bottom:1px solid #ffffff18}.deepss-pet-store-head h2{margin:0;font-size:20px}.deepss-pet-store-head input,.deepss-pet-store-head select{padding:9px 12px;border-radius:10px;border:1px solid #ffffff20;color:white;background:#ffffff0d;font:inherit}.deepss-pet-store-head select{margin-left:auto}.deepss-pet-store-head input{min-width:180px;max-width:420px;flex:1}.deepss-pet-store-head button{color:white}
      #deepss-pet-store-status{font-size:12px;opacity:.65}.deepss-pet-store-body{overflow:auto;padding:22px 24px 48px}.deepss-pet-store-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(190px,1fr));gap:14px;max-width:1500px;margin:auto}.deepss-pet-store-more-sentinel{height:34px;margin:12px auto 0;text-align:center;font-size:12px;line-height:34px;opacity:.55}.deepss-pet-store-more-sentinel[hidden]{display:none}.deepss-pet-source{display:inline-block;margin-left:5px;padding:1px 5px;border-radius:5px;font-size:9px;background:#5278e733;color:#9bb4ff;vertical-align:1px}
      @media(max-width:700px){.deepss-pet-controls{grid-template-columns:1fr}.deepss-pet-store-head{flex-wrap:wrap}.deepss-pet-store-head input{order:3;max-width:none;width:100%;margin:0}}
    `
    document.head.appendChild(style)
  }

  const awesomePreviewURL = slug => `https://codexpet.top/assets/previews/${encodeURIComponent(slug)}/thumbnail.webp`
  const proxiedPreviewURL = (source, id) => `${endpoint}/preview?source=${encodeURIComponent(source)}&id=${encodeURIComponent(id)}&v=2`

  const loadPreview = async img => {
    const url = img.dataset.preview
    if (!url || img.dataset.loaded) return
    img.dataset.loaded = 'true'
    img.onload = () => img.classList.add('loaded')
    img.onerror = () => {
      img.classList.remove('loaded')
      img.removeAttribute('src')
    }
    try {
      if (url.startsWith('https://')) {
        img.src = url
        return
      }
      const cache = await caches.open('deepss-pet-preview-v1')
      let response = await cache.match(url)
      if (!response) {
        response = await fetch(url)
        if (!response.ok) throw new Error(`HTTP ${response.status}`)
        await cache.put(url, response.clone())
      }
      img.src = URL.createObjectURL(await response.blob())
    } catch { img.onerror() }
  }

  const observePreviews = root => {
    if (!previewObserver) previewObserver = new IntersectionObserver(entries => entries.forEach(entry => {
      if (entry.isIntersecting) {
        previewObserver.unobserve(entry.target)
        void loadPreview(entry.target)
      }
    }), { rootMargin: '240px' })
    root.querySelectorAll('img[data-preview]:not([data-loaded])').forEach(img => previewObserver.observe(img))
  }

  const clearPreviews = root => root.querySelectorAll('img[data-preview]').forEach(img => {
    previewObserver?.unobserve(img)
    if (img.src.startsWith('blob:')) URL.revokeObjectURL(img.src)
    img.onload = null
    img.onerror = null
  })

  const localizedName = pet => pet.localized_names?.zh || pet.localized_names?.en || pet.displayName || pet.name || pet.slug || pet.id
  const escapeHTML = value => String(value ?? '').replace(/[&<>'"]/g, character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' })[character])

  const petCard = (pet, mine) => {
    const id = mine ? pet.id : (pet.localID || pet.id || pet.slug)
    const remoteID = pet.remoteID || pet.sourcePetID || pet.slug || pet.id
    const card = document.createElement('article')
    card.className = `deepss-pet-card${id === selectedPetID ? ' selected' : ''}`
    const name = mine ? pet.displayName : localizedName(pet)
    const description = pet.description || (mine ? tr('已安装到 DeepSS', 'Installed in DeepSS') : pet.primary_category || pet.kind || '')
    const inferredSource = ['codex-pets', 'petdex', ...extraSourceDefs.map(item => item.id)].find(sourceID => pet.id?.startsWith(`${sourceID}--`)) || ''
    const source = pet.source || inferredSource || (mine ? 'local' : 'awesome-codex-pet')
    const extraSource = extraSourceDefs.find(item => item.id === source)
    const sourceName = pet.builtIn ? tr('DeepSS 内置', 'Built into DeepSS') : source === 'codex-pets' ? 'Codex Pets' : source === 'petdex' ? 'PetDex' : source === 'awesome-codex-pet' ? 'Awesome' : extraSource?.label || tr('DeepSS 本地', 'DeepSS Local')
    const preview = source === 'petdex'
      ? proxiedPreviewURL('petdex', remoteID)
      : source === 'awesome-codex-pet' || (mine && !pet.previewURL)
        ? proxiedPreviewURL('awesome-codex-pet', remoteID)
        : pet.previewURL || ''
    card.innerHTML = `
      <img class="deepss-pet-preview" alt="${escapeHTML(name)}" data-preview="${escapeHTML(preview)}">
      <h4 title="${escapeHTML(name)}">${escapeHTML(name)}${!mine && sourceName ? `<span class="deepss-pet-source">${sourceName}</span>` : ''}</h4><p>${escapeHTML(description)}</p>
      <div class="deepss-pet-card-foot"><span>${escapeHTML(sourceName)}</span><div class="deepss-pet-card-actions"><button class="deepss-pet-button" type="button"></button></div></div>
    `
    const button = card.querySelector('button')
    if (mine) {
      button.textContent = id === selectedPetID ? tr('使用中', 'Active') : tr('使用', 'Use')
      button.disabled = id === selectedPetID
      button.onclick = async () => {
        button.disabled = true
        button.textContent = tr('切换中…', 'Switching…')
        try { await api('/select', { id }); await refreshMyPets() } catch (error) { button.textContent = error.message; button.disabled = false }
      }
      if (!pet.builtIn) {
        const deleteButton = document.createElement('button')
        deleteButton.className = 'deepss-pet-button deepss-pet-delete'
        deleteButton.type = 'button'
        deleteButton.textContent = tr('删除', 'Delete')
        deleteButton.onclick = async () => {
          if (!window.confirm(tr(`确定删除已下载的宠物“${name}”吗？`, `Delete the downloaded pet “${name}”?`))) return
          deleteButton.disabled = true
          deleteButton.textContent = tr('删除中…', 'Deleting…')
          try {
            await api('/delete', { id })
            await refreshMyPets()
          } catch (error) {
            deleteButton.disabled = false
            deleteButton.textContent = error.message || tr('重试', 'Retry')
          }
        }
        card.querySelector('.deepss-pet-card-actions').appendChild(deleteButton)
      }
    } else {
      const exists = installed.has(id)
      const active = id === selectedPetID
      button.textContent = active ? tr('使用中', 'Active') : exists ? tr('更新', 'Update') : tr('下载', 'Download')
      button.disabled = active
      button.onclick = async () => {
        button.disabled = true
        button.textContent = exists ? tr('更新中…', 'Updating…') : tr('下载中…', 'Downloading…')
        const status = document.querySelector('#deepss-pet-store-status')
        if (status) status.textContent = tr(`正在获取 ${name}…`, `Fetching ${name}…`)
        try {
          await api('/install', { source, id: remoteID })
          await refreshMyPets()
          renderCatalog(document.querySelector('#deepss-pet-store-search')?.value || '')
          if (status) status.textContent = tr(`${name} 已安装并启用`, `${name} installed and activated`)
        } catch (error) {
          button.disabled = false
          button.textContent = tr('重试', 'Retry')
          if (status) status.textContent = tr(`下载失败：${error.message}`, `Download failed: ${error.message}`)
        }
      }
    }
    return card
  }

  const refreshMyPets = async () => {
    const grid = document.querySelector('#deepss-pet-my-grid')
    try {
      const data = await api('/pets')
      selectedPetID = data.selectedPetId
      installed = new Map(data.pets.map(pet => [pet.id, pet]))
      if (grid) {
        clearPreviews(grid)
        grid.replaceChildren(...data.pets.map(pet => petCard(pet, true)))
        observePreviews(grid)
      }
      const count = document.querySelector('#deepss-pet-my-count')
      if (count) count.textContent = tr(`${data.pets.length} 只`, `${data.pets.length} pets`)
      const scale = document.querySelector('#deepss-pet-scale')
      const output = document.querySelector('#deepss-pet-scale-value')
      if (scale && document.activeElement !== scale) scale.value = String(data.scale)
      if (output && document.activeElement !== scale) output.value = Number(data.scale).toFixed(1)
      setHealth(tr('已连接', 'Connected'), true)
    } catch {
      if (grid) grid.innerHTML = `<p>${tr('桌宠服务未启动，请先运行 deepsshpet。', 'DeskPet is not running. Run deepsshpet first.')}</p>`
      setHealth(tr('桌宠未启动', 'DeskPet is not running'), false)
    }
  }

  const matchingAwesomePets = query => {
    const normalized = query.trim().toLowerCase()
    return awesomeCatalog.filter(pet => !normalized || [pet.slug, pet.name, pet.localized_names?.zh, pet.primary_category, ...(pet.collections || [])].some(value => String(value || '').toLowerCase().includes(normalized)))
  }

  const updateCatalogMeta = query => {
    const sourceFilter = document.querySelector('#deepss-pet-store-source')?.value || 'all'
    const awesomeMatches = matchingAwesomePets(query)
    const awesomeShown = Math.min(awesomeVisibleCount, awesomeMatches.length)
    const status = document.querySelector('#deepss-pet-store-status')
    const extraSummary = extraSourceDefs.map(source => `${source.label} ${extraCatalogs[source.id].pets.length} / ${extraCatalogs[source.id].total}`).join(' · ')
    if (status) status.textContent = `Awesome ${awesomeShown} / ${awesomeMatches.length} · Codex Pets ${codexPetsCatalog.length} / ${codexPetsTotal} · PetDex ${petdexCatalog.length} / ${petdexTotal} · ${extraSummary}`
    const allowed = sourceID => sourceFilter === 'all' || sourceFilter === sourceID
    const canLoadAwesome = allowed('awesome-codex-pet') && awesomeShown < awesomeMatches.length && awesomeQuery === query.trim()
    const canLoadCodex = allowed('codex-pets') && codexPetsCatalog.length < codexPetsTotal && codexPetsQuery === query.trim()
    const canLoadPetdex = allowed('petdex') && petdexCatalog.length < petdexTotal && petdexQuery === query.trim()
    const canLoadExtra = extraSourceDefs.some(source => allowed(source.id) && extraCatalogs[source.id].query === query.trim() && extraCatalogs[source.id].pets.length < extraCatalogs[source.id].total)
    const sentinel = document.querySelector('#deepss-pet-store-more-sentinel')
    if (sentinel) sentinel.hidden = !canLoadAwesome && !canLoadCodex && !canLoadPetdex && !canLoadExtra
  }

  const uniquePets = pets => {
    const seen = new Set()
    return pets.filter(pet => {
      const key = String(pet.remoteID || pet.sourcePetID || pet.id || pet.slug).toLowerCase()
      if (seen.has(key)) return false
      seen.add(key)
      return true
    })
  }

  const renderCatalog = query => {
    const grid = document.querySelector('#deepss-pet-store-grid')
    if (!grid) return
    if (awesomeQuery !== query.trim()) {
      awesomeQuery = query.trim()
      awesomeVisibleCount = catalogPageSize
    }
    const awesomeShown = matchingAwesomePets(query).slice(0, awesomeVisibleCount)
    const codexShown = codexPetsQuery === query.trim() ? codexPetsCatalog : []
    const petdexShown = petdexQuery === query.trim() ? petdexCatalog : []
    const extraShown = extraSourceDefs.flatMap(source => extraCatalogs[source.id].query === query.trim() ? extraCatalogs[source.id].pets : [])
    const sourceFilter = document.querySelector('#deepss-pet-store-source')?.value || 'all'
    const sourcePets = { 'awesome-codex-pet': awesomeShown, 'codex-pets': codexShown, petdex: petdexShown, ...Object.fromEntries(extraSourceDefs.map(source => [source.id, extraCatalogs[source.id].pets])) }
    const shown = uniquePets(sourceFilter === 'all' ? [...awesomeShown, ...codexShown, ...petdexShown, ...extraShown] : sourcePets[sourceFilter] || [])
    clearPreviews(grid)
    grid.replaceChildren(...shown.map(pet => petCard(pet, false)))
    observePreviews(grid)
    updateCatalogMeta(query)
  }

  const normalizeCodexPet = pet => ({
    ...pet,
    source: 'codex-pets',
    remoteID: pet.id,
    localID: `codex-pets--${pet.id}`,
    previewURL: pet.posterUrl || pet.previewUrl,
  })

  const normalizePetdexPet = pet => ({
    ...pet,
    source: 'petdex',
    remoteID: pet.id,
    localID: `petdex--${pet.id}`,
    previewURL: proxiedPreviewURL('petdex', pet.id),
  })

  const loadCodexPets = async (query, page = 1, append = false) => {
    const data = await api('/catalog', { source: 'codex-pets', page, pageSize: catalogPageSize, query })
    const next = (data.pets || []).map(normalizeCodexPet)
    codexPetsCatalog = append ? [...codexPetsCatalog, ...next] : next
    codexPetsPage = Number(data.page || page)
    codexPetsTotal = Number(data.total || next.length)
    codexPetsQuery = query
    return next
  }

  const loadPetdex = async (query, page = 1, append = false) => {
    const data = await api('/catalog', { source: 'petdex', page, pageSize: catalogPageSize, query })
    const next = (data.pets || []).map(normalizePetdexPet)
    petdexCatalog = append ? [...petdexCatalog, ...next] : next
    petdexPage = Number(data.page || page)
    petdexTotal = Number(data.total || next.length)
    petdexQuery = query
    return next
  }

  const loadExtraSource = async (source, query, page = 1, append = false) => {
    const data = await api('/catalog', { source, page, pageSize: catalogPageSize, query })
    const next = (data.pets || []).map(pet => ({
      ...pet,
      source,
      remoteID: pet.id,
      localID: `${source}--${pet.id}`,
    }))
    const state = extraCatalogs[source]
    state.pets = append ? [...state.pets, ...next] : next
    state.page = Number(data.page || page)
    state.total = Number(data.total || next.length)
    state.query = query
    return next
  }

  const loadCatalog = async (query = '') => {
    const status = document.querySelector('#deepss-pet-store-status')
    if (status) status.textContent = tr('正在同步宠物目录…', 'Syncing pet catalogs…')
    try {
      const tasks = [loadCodexPets(query), loadPetdex(query), ...extraSourceDefs.map(source => loadExtraSource(source.id, query))]
      if (!awesomeCatalog.length) tasks.push(fetch(`${catalogURL}?t=${Date.now()}`, { cache: 'no-store' }).then(response => {
        if (!response.ok) throw new Error(`HTTP ${response.status}`)
        return response.json()
      }).then(pets => {
        awesomeCatalog = pets.map(pet => ({ ...pet, source: 'awesome-codex-pet', remoteID: pet.slug, localID: pet.slug, previewURL: awesomePreviewURL(pet.slug) }))
      }))
      const outcomes = await Promise.allSettled(tasks)
      if (outcomes.every(outcome => outcome.status === 'rejected')) throw outcomes[0].reason
      renderCatalog(query)
    } catch (error) {
      if (status) status.textContent = tr(`目录加载失败：${error.message}`, `Catalog failed to load: ${error.message}`)
    }
  }

  const loadMoreCatalog = async () => {
    if (catalogLoadingMore) return
    const store = document.querySelector('#deepss-pet-store')
    if (!store?.classList.contains('open')) return
    const query = store.querySelector('#deepss-pet-store-search').value.trim()
    const source = store.querySelector('#deepss-pet-store-source').value
    const tasks = []
    const additions = []
    const awesomeMatches = matchingAwesomePets(query)
    const availableSources = []
    if (awesomeQuery === query && awesomeVisibleCount < awesomeMatches.length) availableSources.push('awesome-codex-pet')
    if (codexPetsQuery === query && codexPetsCatalog.length < codexPetsTotal) availableSources.push('codex-pets')
    if (petdexQuery === query && petdexCatalog.length < petdexTotal) availableSources.push('petdex')
    extraSourceDefs.forEach(source => {
      const state = extraCatalogs[source.id]
      if (state.query === query && state.pets.length < state.total) availableSources.push(source.id)
    })
    const sourcesToLoad = source === 'all' && availableSources.length
      ? [availableSources[catalogSourceCursor++ % availableSources.length]]
      : [source]
    if (sourcesToLoad.includes('awesome-codex-pet') && awesomeQuery === query && awesomeVisibleCount < awesomeMatches.length) {
      const previousCount = awesomeVisibleCount
      awesomeVisibleCount = Math.min(awesomeMatches.length, awesomeVisibleCount + catalogPageSize)
      additions.push(...awesomeMatches.slice(previousCount, awesomeVisibleCount))
    }
    if (sourcesToLoad.includes('codex-pets') && codexPetsQuery === query && codexPetsCatalog.length < codexPetsTotal) {
      tasks.push(loadCodexPets(query, codexPetsPage + 1, true))
    }
    if (sourcesToLoad.includes('petdex') && petdexQuery === query && petdexCatalog.length < petdexTotal) {
      tasks.push(loadPetdex(query, petdexPage + 1, true))
    }
    extraSourceDefs.forEach(sourceDef => {
      const state = extraCatalogs[sourceDef.id]
      if (sourcesToLoad.includes(sourceDef.id) && state.query === query && state.pets.length < state.total) {
        tasks.push(loadExtraSource(sourceDef.id, query, state.page + 1, true))
      }
    })
    if (!tasks.length && !additions.length) return
    catalogLoadingMore = true
    const sentinel = store.querySelector('#deepss-pet-store-more-sentinel')
    if (sentinel) sentinel.textContent = tr('正在加载更多宠物…', 'Loading more pets…')
    try {
      const outcomes = await Promise.allSettled(tasks)
      if (store.querySelector('#deepss-pet-store-search').value.trim() !== query || store.querySelector('#deepss-pet-store-source').value !== source) {
        renderCatalog(store.querySelector('#deepss-pet-store-search').value.trim())
        return
      }
      outcomes.forEach(outcome => { if (outcome.status === 'fulfilled') additions.push(...outcome.value) })
      const grid = store.querySelector('#deepss-pet-store-grid')
      grid.append(...additions.map(pet => petCard(pet, false)))
      observePreviews(grid)
      updateCatalogMeta(query)
      const failed = outcomes.find(outcome => outcome.status === 'rejected')
      if (failed) store.querySelector('#deepss-pet-store-status').textContent = tr(`部分目录加载失败：${failed.reason?.message || '请稍后重试'}`, `Some catalogs failed: ${failed.reason?.message || 'try again later'}`)
    } finally {
      catalogLoadingMore = false
      if (sentinel) sentinel.textContent = tr('继续向下滚动加载', 'Scroll down to load more')
    }
  }

  const ensureStore = () => {
    if (document.querySelector('#deepss-pet-store')) return
    const store = document.createElement('div')
    store.id = 'deepss-pet-store'
    store.setAttribute('role', 'dialog')
    store.setAttribute('aria-label', tr('找找新宠物', 'Find new pets'))
    store.innerHTML = `
      <div class="deepss-pet-store-head"><h2>🐾 ${tr('找找新宠物', 'Find new pets')}</h2><span id="deepss-pet-store-status"></span><select id="deepss-pet-store-source" aria-label="${tr('宠物来源', 'Pet source')}"><option value="all">${tr('全部来源', 'All sources')}</option><option value="awesome-codex-pet">Awesome</option><option value="codex-pets">Codex Pets</option><option value="petdex">PetDex</option>${extraSourceDefs.map(source => `<option value="${source.id}">${source.label}</option>`).join('')}</select><input id="deepss-pet-store-search" type="search" placeholder="${tr('搜索名称或分类…', 'Search names or categories…')}"><button class="deepss-pet-button" id="deepss-pet-store-close" type="button">${tr('关闭', 'Close')}</button></div>
      <div class="deepss-pet-store-body"><div class="deepss-pet-store-grid" id="deepss-pet-store-grid"></div><div class="deepss-pet-store-more-sentinel" id="deepss-pet-store-more-sentinel">${tr('继续向下滚动加载', 'Scroll down to load more')}</div></div>
    `
    document.body.appendChild(store)
    store.querySelector('#deepss-pet-store-close').onclick = () => store.classList.remove('open')
    store.querySelector('#deepss-pet-store-source').onchange = () => {
      catalogSourceCursor = 0
      store.querySelector('.deepss-pet-store-body').scrollTop = 0
      renderCatalog(store.querySelector('#deepss-pet-store-search').value)
    }
    store.querySelector('#deepss-pet-store-search').oninput = event => {
      const query = event.target.value.trim()
      clearTimeout(catalogSearchTimer)
      catalogSourceCursor = 0
      store.querySelector('.deepss-pet-store-body').scrollTop = 0
      renderCatalog(query)
      catalogSearchTimer = setTimeout(() => void loadCatalog(query), 320)
    }
    catalogMoreObserver = new IntersectionObserver(entries => {
      if (entries.some(entry => entry.isIntersecting)) void loadMoreCatalog()
    }, { root: store.querySelector('.deepss-pet-store-body'), rootMargin: '180px 0px' })
    catalogMoreObserver.observe(store.querySelector('#deepss-pet-store-more-sentinel'))
  }

  const openStore = async () => {
    ensureStore()
    document.querySelector('#deepss-pet-store').classList.add('open')
    await refreshMyPets()
    const query = document.querySelector('#deepss-pet-store-search').value.trim()
    await loadCatalog(query)
  }

  const refreshPhrases = async () => {
    const input = document.querySelector('#deepss-pet-phrases')
    if (!input || document.activeElement === input) return
    try {
      const data = await api('/phrases')
      input.value = (data.phrases || []).join('\n')
    } catch {}
  }

  const settingsPage = () => {
    const page = document.createElement('div')
    page.id = 'deepss-pet-settings-page'
    page.hidden = true
    page.innerHTML = `
      <div class="deepss-pet-head"><div><h2>${tr('桌面宠物', 'Desktop Pet')}</h2><p>${tr('让你的宠物在整个桌面上陪伴 DeepSeek Harness 任务。', 'Let a desktop companion follow your DeepSeek Harness tasks across your desktop.')}</p></div><button class="deepss-pet-primary" id="deepss-pet-find" type="button">${tr('找找新宠物', 'Find new pets')}</button></div>
      <div class="deepss-pet-controls">
        <div class="deepss-pet-setting-card"><label for="deepss-pet-mode">${tr('动画状态', 'Animation state')}</label><select id="deepss-pet-mode"><option value="auto">${tr('自动跟随任务', 'Follow tasks automatically')}</option><option value="idle">${tr('待机', 'Idle')}</option><option value="waving">${tr('挥手', 'Wave')}</option><option value="jumping">${tr('跳跃', 'Jump')}</option><option value="waiting">${tr('等待', 'Waiting')}</option><option value="running">${tr('运行中', 'Running')}</option><option value="review">${tr('检查', 'Review')}</option><option value="failed">${tr('失败', 'Failed')}</option></select></div>
        <div class="deepss-pet-setting-card"><label for="deepss-pet-scale">${tr('宠物大小', 'Pet size')} <small>${tr('默认 0.5', 'Default 0.5')}</small></label><div class="deepss-pet-range-line"><input id="deepss-pet-scale" type="range" min="0.2" max="1.5" step="0.1" value="0.5"><output id="deepss-pet-scale-value">0.5</output></div></div>
        <div class="deepss-pet-setting-card"><label>${tr('显示状态', 'Visibility')}</label><div class="deepss-pet-inline-buttons"><button class="deepss-pet-button" data-pet-visible="true" type="button">${tr('显示', 'Show')}</button><button class="deepss-pet-button" data-pet-visible="false" type="button">${tr('隐藏', 'Hide')}</button><span data-deepss-pet-health data-connected="true">${tr('已连接', 'Connected')}</span></div></div>
        <div class="deepss-pet-setting-card deepss-pet-setting-card-wide"><label for="deepss-pet-phrases">${tr('宠物快捷语', 'Pet quick phrases')} <small>${tr('每行一句，单击宠物时会随机配合动作显示', 'One phrase per line; clicking the pet shows one with a random action.')}</small></label><textarea id="deepss-pet-phrases" maxlength="3000" placeholder="${tr('主人～坐久了，站起来休息休息吧', "You've been sitting for a while—time to stand up and stretch!")}"></textarea><div class="deepss-pet-phrase-foot"><small id="deepss-pet-phrase-status"></small><button class="deepss-pet-primary" id="deepss-pet-phrase-save" type="button">${tr('保存快捷语', 'Save phrases')}</button></div></div>
      </div>
      <div class="deepss-pet-section-title"><h3>${tr('我的宠物', 'My pets')}</h3><span id="deepss-pet-my-count"></span></div><div class="deepss-pet-grid" id="deepss-pet-my-grid"></div>
    `
    page.querySelector('#deepss-pet-find').onclick = () => void openStore()
    const select = page.querySelector('#deepss-pet-mode')
    select.value = mode
    select.onchange = () => {
      mode = select.value
      localStorage.setItem('deepss-pet-mode', mode)
      lastPayload = ''
      void sync()
    }
    const scale = page.querySelector('#deepss-pet-scale')
    const output = page.querySelector('#deepss-pet-scale-value')
    scale.oninput = () => { output.value = Number(scale.value).toFixed(1) }
    scale.onchange = () => {
      clearTimeout(scaleTimer)
      scaleTimer = setTimeout(() => void api('/control', { scale: Number(scale.value) }), 20)
    }
    page.querySelectorAll('[data-pet-visible]').forEach(button => {
      button.onclick = async () => {
        try { await api('/control', { visible: button.dataset.petVisible === 'true', locale: harnessLocale() }); setHealth(tr('已连接', 'Connected'), true) }
        catch { setHealth(tr('桌宠未启动', 'DeskPet is not running'), false) }
      }
    })
    const phraseInput = page.querySelector('#deepss-pet-phrases')
    const phraseStatus = page.querySelector('#deepss-pet-phrase-status')
    page.querySelector('#deepss-pet-phrase-save').onclick = async event => {
      const button = event.currentTarget
      const phrases = phraseInput.value.split('\n').map(value => value.trim()).filter(Boolean)
      button.disabled = true
      phraseStatus.textContent = tr('正在保存…', 'Saving…')
      try {
        const data = await api('/phrases', { phrases })
        phraseInput.value = data.phrases.join('\n')
        phraseStatus.textContent = tr(`已保存 ${data.phrases.length} 句，单击桌宠即可触发`, `Saved ${data.phrases.length} phrases; click the pet to trigger one`)
      } catch (error) {
        phraseStatus.textContent = error.message || tr('保存失败', 'Save failed')
      } finally {
        button.disabled = false
      }
    }
    void refreshPhrases()
    return page
  }

  const mountSettingsSection = () => {
    const dialog = [...document.querySelectorAll('[role="dialog"]')].find(candidate =>
      [...candidate.querySelectorAll('nav button')].some(button => /^通用设置$|^General$/.test((button.textContent || '').trim())))
    if (!dialog || dialog.querySelector('#deepss-pet-nav')) return
    const navButtons = [...dialog.querySelectorAll('nav button')]
    const general = navButtons.find(button => /^通用设置$|^General$/.test((button.textContent || '').trim()))
    const active = dialog.querySelector('nav button[aria-current="true"]') || general
    const inactive = navButtons.find(button => button !== active)
    const activeOnlyClasses = [...active.classList].filter(name => !inactive?.classList.contains(name))
    const navButton = general.cloneNode(true)
    navButton.id = 'deepss-pet-nav'
    navButton.removeAttribute('aria-current')
    activeOnlyClasses.forEach(name => navButton.classList.remove(name))
    navButton.innerHTML = `<span aria-hidden="true">🐾</span><span>${tr('桌面宠物', 'Desktop Pet')}</span>`
    general.parentElement.appendChild(navButton)

    const nativeSection = dialog.querySelector('[data-slot="settings.section"]')
    const options = nativeSection?.parentElement
    if (!options) return
    const page = settingsPage()
    options.appendChild(page)

    const deactivate = () => {
      navButton.removeAttribute('aria-current')
      activeOnlyClasses.forEach(name => navButton.classList.remove(name))
      page.hidden = true
      const currentNativeSection = dialog.querySelector('[data-slot="settings.section"]')
      if (currentNativeSection) currentNativeSection.style.display = ''
    }
    navButtons.forEach(button => button.addEventListener('click', () => setTimeout(deactivate)))
    navButton.onclick = () => {
      navButtons.forEach(button => {
        button.removeAttribute('aria-current')
        activeOnlyClasses.forEach(name => button.classList.remove(name))
      })
      navButton.setAttribute('aria-current', 'true')
      activeOnlyClasses.forEach(name => navButton.classList.add(name))
      const currentNativeSection = dialog.querySelector('[data-slot="settings.section"]')
      if (currentNativeSection) currentNativeSection.style.display = 'none'
      page.hidden = false
      void refreshMyPets()
      void refreshPhrases()
    }
  }

  const mount = () => {
    installStyles()
    ensureStore()
    const observer = new MutationObserver(() => {
      mountSettingsSection()
      clearTimeout(syncTimer)
      syncTimer = setTimeout(() => void sync(), 180)
    })
    observer.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['aria-label'] })
    let mountedLocale = harnessLocale()
    const localeObserver = new MutationObserver(() => {
      const nextLocale = harnessLocale()
      if (nextLocale === mountedLocale) return
      mountedLocale = nextLocale
      lastPayload = ''
      document.querySelector('#deepss-pet-store')?.remove()
      const page = document.querySelector('#deepss-pet-settings-page')
      const nav = document.querySelector('#deepss-pet-nav')
      const nativeSection = page?.parentElement?.querySelector('[data-slot="settings.section"]')
      if (nativeSection) nativeSection.style.display = ''
      page?.remove()
      nav?.remove()
      ensureStore()
      mountSettingsSection()
      void sync()
    })
    localeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ['lang'] })
    setInterval(() => void sync(), 2500)
    mountSettingsSection()
    void sync()
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mount, { once: true })
  else mount()
})()
