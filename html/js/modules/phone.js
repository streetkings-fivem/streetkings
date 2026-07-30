(function (window, $) {
  'use strict';

  var SK      = window.StreetKings;
  var elPhone = document.getElementById('viewPhone');
  var currentApp = null;
  var appOpenTimer = null;
  var phoneMode = 'default';
  var eventPhoneState = null;
  var missionPhoneState = null;
  var elPhoneEventTitle = document.getElementById('phoneEventTitle');
  var elPhoneEventName = document.getElementById('phoneEventName');
  var elPhoneEventCopy = document.getElementById('phoneEventCopy');
  var elPhoneEventRecover = document.getElementById('phoneEventRecover');
  var elPhoneEventForfeit = document.getElementById('phoneEventForfeit');
  var elPhoneEventNote = document.getElementById('phoneEventNote');
  var elPhoneMissionName = document.getElementById('phoneMissionName');
  var elPhoneMissionForfeit = document.getElementById('phoneMissionForfeit');
  var elPhoneBalance = document.getElementById('phoneBalance');

  var appHandlers = {};
  var controllerAdapters = {};
  var pendingAppData = {};
  var controllerEnabled = false;
  var HOME_GRID_COLUMNS = 4;
  var controllerGlyphs = SK.controllerGlyphs;

  window.SKPhone = {
    registerApp: function (appId, handler) { appHandlers[appId] = handler; },
    registerControllerAdapter: function (appId, adapter) { controllerAdapters[appId] = adapter || {}; },
    refreshControllerFocus: function (options) { scheduleControllerRefresh(options); },
    focusControllerElement: function (el) { focusControllerElement(el); },
    isControllerMode: function () { return controllerEnabled; },
    setCashBalance: function (amount) { updateCashBalance(amount); }
  };

  function updateTime() {
    var now = new Date();
    var h   = now.getHours().toString().padStart(2, '0');
    var m   = now.getMinutes().toString().padStart(2, '0');
    document.getElementById('phoneTime').textContent = h + ':' + m;
  }

  function formatMoney(value) {
    return '$' + Math.floor(Number(value || 0)).toLocaleString('en-US');
  }

  function updateCashBalance(amount) {
    if (!elPhoneBalance) {
      return;
    }

    elPhoneBalance.textContent = formatMoney(amount);
  }

  function refreshCashBalance() {
    SK.nui.post('phone:stats:getData').done(function (data) {
      updateCashBalance(data && data.cash);
    });
  }

  function makeBackChevron() {
    var ns = 'http://www.w3.org/2000/svg';
    var svg = document.createElementNS(ns, 'svg');
    svg.setAttribute('class', 'phone-app-back-chevron');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('fill', 'none');
    svg.setAttribute('stroke', 'currentColor');
    svg.setAttribute('stroke-width', '2.5');
    svg.setAttribute('stroke-linecap', 'round');
    svg.setAttribute('stroke-linejoin', 'round');
    var path = document.createElementNS(ns, 'path');
    path.setAttribute('d', 'm15 18-6-6 6-6');
    svg.appendChild(path);
    return svg;
  }

  function renderBackButtons() {
    var buttons = elPhone.querySelectorAll('.phone-app-back');
    for (var i = 0; i < buttons.length; i++) {
      if (controllerEnabled) {
        buttons[i].innerHTML = controllerGlyphs.getHtml('B', 'phone-app-back-icon') + '<span>Back</span>';
      } else {
        var btn = buttons[i];
        while (btn.firstChild) btn.removeChild(btn.firstChild);
        btn.appendChild(makeBackChevron());
        var label = document.createElement('span');
        label.textContent = 'Back';
        btn.appendChild(label);
      }
    }
  }

  function activeViewEl() {
    return currentApp
      ? document.getElementById('phoneApp' + currentApp)
      : document.getElementById('phoneHome');
  }

  function currentControllerAdapter() {
    if (currentApp) {
      return controllerAdapters[currentApp] || null;
    }
    return homeControllerAdapter;
  }

  function getHomeAppButtons() {
    var home = document.getElementById('phoneHome');
    if (!home) return [];
    return Array.prototype.slice.call(home.querySelectorAll('.phone-app[data-app]'));
  }

  var homeControllerAdapter = {
    getFocusables: function () {
      return getHomeAppButtons();
    },
    getPreferredFocus: function (list) {
      return list[0] || null;
    },
    onDirection: function (direction, focusedEl) {
      var apps = getHomeAppButtons();
      if (!apps.length || !focusedEl) {
        return false;
      }

      var index = apps.indexOf(focusedEl);
      if (index === -1) {
        return false;
      }

      var row = Math.floor(index / HOME_GRID_COLUMNS);
      var col = index % HOME_GRID_COLUMNS;
      var targetIndex = index;

      if (direction === 'left') {
        if (col === 0) {
          return true;
        }
        targetIndex = index - 1;
      } else if (direction === 'right') {
        if (col === HOME_GRID_COLUMNS - 1 || index + 1 >= apps.length) {
          return true;
        }
        targetIndex = index + 1;
      } else if (direction === 'up') {
        if (row === 0) {
          return true;
        }
        targetIndex = index - HOME_GRID_COLUMNS;
      } else if (direction === 'down') {
        targetIndex = index + HOME_GRID_COLUMNS;
        if (targetIndex >= apps.length) {
          return true;
        }
      } else {
        return false;
      }

      if (apps[targetIndex]) {
        focusControllerElement(apps[targetIndex]);
        return true;
      }

      return true;
    }
  };

  var controllerNav = SK.controllerFriendly.createNavigator({
    isActive: function () {
      return elPhone.classList.contains('is-active');
    },
    onModeChange: function (enabled) {
      controllerEnabled = enabled;
      elPhone.classList.toggle('is-controller-nav', enabled);
      renderBackButtons();
    },
    getFocusables: function () {
      return collectFocusables();
    },
    getPreferredFocus: function (list) {
      return getPreferredFocusable(list);
    },
    onActivate: function (focusedEl) {
      var adapter = currentControllerAdapter();
      return !!(adapter && typeof adapter.onActivate === 'function' && adapter.onActivate(focusedEl));
    },
    onBack: function () {
      var adapter = currentControllerAdapter();
      if (adapter && typeof adapter.onBack === 'function' && adapter.onBack()) {
        return true;
      }

      if (phoneMode === 'event' || phoneMode === 'mission') {
        requestClose();
        return true;
      }

      if (currentApp) {
        showHome();
        return true;
      }

      requestClose();
      return true;
    },
    onDirection: function (direction, focusedEl) {
      var adapter = currentControllerAdapter();
      return !!(adapter && typeof adapter.onDirection === 'function' && adapter.onDirection(direction, focusedEl));
    },
    onAnalog: function (lookX, lookY) {
      var adapter = currentControllerAdapter();
      if (!adapter || typeof adapter.onAnalogScroll !== 'function') {
        return;
      }
      adapter.onAnalogScroll(lookX, lookY);
    }
  });

  function setControllerEnabled(nextEnabled) {
    controllerNav.setEnabled(nextEnabled);
  }

  function focusControllerElement(el) {
    controllerNav.focusElement(el);
  }

  function scheduleControllerRefresh(options) {
    controllerNav.refresh(options);
  }

  function collectFocusables() {
    var root = activeViewEl();
    if (!root) return [];

    var adapter = currentControllerAdapter();
    var selector = [
      'button:not([disabled])',
      'select:not([disabled]):not([data-controller-skip="true"])',
      'input[type="range"]:not([disabled]):not([data-controller-skip="true"])',
      '[data-controller-focusable="true"]:not([data-controller-skip="true"])'
    ].join(', ');
    var nodes = root.querySelectorAll(selector);
    var list = [];
    var seen = [];
    var i;

    for (i = 0; i < nodes.length; i++) {
      if (nodes[i].getAttribute('data-controller-skip') === 'true') continue;
      if (nodes[i].classList && nodes[i].classList.contains('phone-app-back')) continue;
      if (!controllerNav.isVisible(nodes[i])) continue;
      if (seen.indexOf(nodes[i]) !== -1) continue;
      seen.push(nodes[i]);
      list.push(nodes[i]);
    }

    if (adapter && typeof adapter.getFocusables === 'function') {
      var adapted = adapter.getFocusables(root, list.slice());
      if (Array.isArray(adapted)) {
        list = [];
        seen = [];
        for (i = 0; i < adapted.length; i++) {
          if (!controllerNav.isVisible(adapted[i])) continue;
          if (seen.indexOf(adapted[i]) !== -1) continue;
          seen.push(adapted[i]);
          list.push(adapted[i]);
        }
      }
    }

    return list;
  }

  function getPreferredFocusable(list) {
    var adapter = currentControllerAdapter();
    if (adapter && typeof adapter.getPreferredFocus === 'function') {
      var preferred = adapter.getPreferredFocus(list.slice());
      if (preferred && list.indexOf(preferred) !== -1) {
        return preferred;
      }
    }

    var selectors = [
      '.is-selected',
      '.is-active',
      '[data-controller-preferred="true"]'
    ];
    for (var i = 0; i < selectors.length; i++) {
      for (var j = 0; j < list.length; j++) {
        if (list[j].matches && list[j].matches(selectors[i])) {
          return list[j];
        }
      }
    }

    return list[0] || null;
  }

  function observeControllerRoot() {
    var root = activeViewEl();
    controllerNav.observeRoot(root);
  }

  function handleControllerInput(action) {
    controllerNav.handleInput(action);
  }

  function handleControllerAnalog(data) {
    controllerNav.handleAnalog(
      typeof data.lookX === 'number' ? data.lookX : 0,
      typeof data.lookY === 'number' ? data.lookY : 0
    );
  }

  function showApp(appId) {
    if (currentApp && currentApp !== appId) {
      document.getElementById('phoneApp' + currentApp).classList.remove('is-active');
    }
    document.getElementById('phoneHome').classList.remove('is-active');
    document.getElementById('phoneApp' + appId).classList.add('is-active');
    currentApp = appId;
    observeControllerRoot();
    if (appOpenTimer) {
      clearTimeout(appOpenTimer);
      appOpenTimer = null;
    }
    appOpenTimer = setTimeout(function () {
      appOpenTimer = null;
      if (currentApp !== appId) return;
      var launchData = pendingAppData[appId] || null;
      pendingAppData[appId] = null;
      if (appHandlers[appId]) { appHandlers[appId](launchData); }
      if (controllerAdapters[appId] && typeof controllerAdapters[appId].onAppShown === 'function') {
        controllerAdapters[appId].onAppShown(launchData);
      }
      if (controllerEnabled) {
        scheduleControllerRefresh({ retainCurrent: false });
      }
    }, 0);
  }

  function showHome() {
    if (phoneMode === 'event' || phoneMode === 'mission') {
      return;
    }
    if (appOpenTimer) {
      clearTimeout(appOpenTimer);
      appOpenTimer = null;
    }
    if (currentApp) {
      document.getElementById('phoneApp' + currentApp).classList.remove('is-active');
      currentApp = null;
    }
    document.getElementById('phoneHome').classList.add('is-active');
    observeControllerRoot();
    if (controllerEnabled) {
      scheduleControllerRefresh({ retainCurrent: false });
    }
  }

  function resetPhoneView() {
    if (appOpenTimer) {
      clearTimeout(appOpenTimer);
      appOpenTimer = null;
    }
    if (currentApp) {
      document.getElementById('phoneApp' + currentApp).classList.remove('is-active');
      currentApp = null;
    }
    document.getElementById('phoneHome').classList.add('is-active');
    observeControllerRoot();
  }

  function renderEventPhone() {
    if (!eventPhoneState) return;
    if (elPhoneEventTitle) {
      elPhoneEventTitle.textContent = (eventPhoneState.actionMode === 'lobbyHostClose' || eventPhoneState.actionMode === 'lobbyHostStart')
        ? 'Multiplayer Lobby'
        : (eventPhoneState.isMultiplayer ? 'Multiplayer Event' : 'Event Menu');
    }
    if (elPhoneEventName) {
      elPhoneEventName.textContent = eventPhoneState.eventName;
    }
    if (elPhoneEventCopy) {
      elPhoneEventCopy.textContent = eventPhoneState.actionMode === 'lobbyHostClose'
        ? 'Close your empty lobby and return to free roam.'
        : (eventPhoneState.actionMode === 'lobbyHostStart'
        ? 'Your lobby has racers ready. Start the race immediately.'
        : (eventPhoneState.isMultiplayer
        ? 'Recover to the last checkpoint, or close the phone to keep racing.'
        : 'Recover to the last checkpoint or forfeit the run.'));
    }
    if (elPhoneEventRecover) {
      elPhoneEventRecover.textContent = eventPhoneState.actionMode === 'lobbyHostClose'
        ? 'Close Lobby'
        : (eventPhoneState.actionMode === 'lobbyHostStart'
        ? 'Start Race Now'
        : 'Recover to Last Checkpoint');
      elPhoneEventRecover.disabled = eventPhoneState.canRecover !== true;
    }
    if (elPhoneEventForfeit) {
      elPhoneEventForfeit.textContent = 'Forfeit Event';
      elPhoneEventForfeit.disabled = eventPhoneState.canForfeit !== true;
      elPhoneEventForfeit.style.display = (eventPhoneState.actionMode === 'lobbyHostClose' || eventPhoneState.actionMode === 'lobbyHostStart') ? 'none' : '';
    }
    if (elPhoneEventNote) {
      elPhoneEventNote.textContent = eventPhoneState.actionMode === 'lobbyHostClose'
        ? 'Closing the phone keeps the lobby open. Use Close Lobby to leave it.'
        : (eventPhoneState.actionMode === 'lobbyHostStart'
        ? 'Closing the phone keeps the lobby open. Use Start Race Now to launch immediately.'
        : (eventPhoneState.canForfeit === true
        ? 'Closing the phone resumes the event immediately.'
        : 'Forfeit is disabled while you are in a multiplayer event.'));
    }
  }

  function renderMissionPhone() {
    if (!missionPhoneState) return;
    if (elPhoneMissionName) {
      elPhoneMissionName.textContent = missionPhoneState.missionName || 'Active Mission';
    }
  }

  function openPhone(data) {
    phoneMode = data && data.mode ? data.mode : 'default';
    eventPhoneState = data && data.eventPhone ? data.eventPhone : null;
    missionPhoneState = data && data.missionPhone ? data.missionPhone : null;
    elPhone.dataset.mode = phoneMode;
    elPhone.dataset.slide = data && data.slideDirection ? data.slideDirection : 'bottom';
    elPhone.classList.add('is-active');
    setControllerEnabled(!!(data && data.controller));
    updateTime();
    refreshCashBalance();
    if (phoneMode === 'event') {
      renderEventPhone();
      showApp('Event');
      return;
    }
    if (phoneMode === 'mission') {
      renderMissionPhone();
      showApp('Mission');
      return;
    }
    if (data && data.appId) {
      pendingAppData[data.appId] = data.appData || null;
      showApp(data.appId);
      return;
    }
    if (window.SKMessages && window.SKMessages.pendingSender) {
      showApp('Messages');
      return;
    }
    showHome();
  }

  function focusApp(data) {
    if (!data || !data.appId) return;
    pendingAppData[data.appId] = data.appData || null;
    showApp(data.appId);
  }

  function closePhone() {
    elPhone.classList.remove('is-active');
    phoneMode = 'default';
    eventPhoneState = null;
    missionPhoneState = null;
    elPhone.dataset.mode = 'default';
    setControllerEnabled(false);
    controllerNav.disconnectObserver();
    setTimeout(resetPhoneView, 400);
  }

  function requestClose() {
    SK.nui.post('phone:close').always(closePhone);
  }

  $(elPhone).on('click', '.phone-app[data-app]', function () { showApp($(this).data('app')); });
  $(elPhone).on('click', '.phone-app-back', showHome);
  $(elPhone).on('click', '.phone-home-btn', function () {
    if (phoneMode === 'event' || phoneMode === 'mission') {
      requestClose();
      return;
    }
    if (currentApp) { showHome(); } else { requestClose(); }
  });
  function clearControllerModeFromNonPadInput() {
    if (controllerEnabled) {
      setControllerEnabled(false);
    }
  }

  elPhone.addEventListener('mousedown', clearControllerModeFromNonPadInput, true);
  elPhone.addEventListener('mousemove', clearControllerModeFromNonPadInput, true);
  elPhone.addEventListener('wheel', clearControllerModeFromNonPadInput, true);
  document.addEventListener('keydown', function () {
    if (!elPhone.classList.contains('is-active')) return;
    clearControllerModeFromNonPadInput();
  }, true);

  if (elPhoneEventRecover) {
    elPhoneEventRecover.addEventListener('click', function () {
      if (elPhoneEventRecover.disabled) return;
      if (eventPhoneState && eventPhoneState.actionMode === 'lobbyHostClose') {
        SK.nui.post('phone:multiplayerLobby:close');
        return;
      }
      if (eventPhoneState && eventPhoneState.actionMode === 'lobbyHostStart') {
        SK.nui.post('phone:multiplayerLobby:startNow');
        return;
      }
      SK.nui.post('phone:event:recover');
    });
  }

  if (elPhoneEventForfeit) {
    elPhoneEventForfeit.addEventListener('click', function () {
      if (elPhoneEventForfeit.disabled) return;
      SK.nui.post('phone:event:forfeit');
    });
  }

  window.SKPhone.registerApp('Event', function () {
    renderEventPhone();
  });

  if (elPhoneMissionForfeit) {
    elPhoneMissionForfeit.addEventListener('click', function () {
      SK.nui.post('phone:mission:forfeit');
    });
  }

  window.SKPhone.registerApp('Mission', function () {
    renderMissionPhone();
  });

  document.addEventListener('keydown', function (e) {
    if (!elPhone.classList.contains('is-active')) return;
    if (e.key === 'Escape' || e.key === 'Tab') {
      e.preventDefault();
      requestClose();
    }
  });

  window.addEventListener('message', function (e) {
    if (e.data.type === 'phone:open')  { openPhone(e.data); }
    if (e.data.type === 'phone:focusApp') { focusApp(e.data); }
    if (e.data.type === 'phone:close') { closePhone(); }
    if (e.data.type === 'phone:controllerMode') { setControllerEnabled(!!e.data.enabled); }
    if (e.data.type === 'phone:controllerInput') { handleControllerInput(e.data.action); }
    if (e.data.type === 'phone:controllerAnalog') { handleControllerAnalog(e.data); }
  });

  controllerGlyphs.onChange(function () {
    renderBackButtons();
  });

  renderBackButtons();
  setInterval(updateTime, 30000);
})(window, jQuery);
