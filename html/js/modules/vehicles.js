(function (window) {
  'use strict';

  var SK = window.StreetKings;

  var state = {
    vehicles: [],
    activeVehicleId: '',
    selectedVehicleId: '',
  };

  var els = {};

  function resolveEls() {
    els.list = document.getElementById('vehiclesList');
    els.panel = document.getElementById('vehiclesPanel');
  }

  function escapeHtml(str) {
    var el = document.createElement('span');
    el.appendChild(document.createTextNode(str == null ? '' : String(str)));
    return el.innerHTML;
  }

  function pad(n) {
    return n < 10 ? '0' + n : '' + n;
  }

  function formatTime(ms) {
    var totalSec = ms / 1000;
    var minutes = Math.floor(totalSec / 60);
    var seconds = Math.floor(totalSec % 60);
    var centiseconds = Math.floor((totalSec % 1) * 100);
    return minutes + ':' + pad(seconds) + '.' + pad(centiseconds);
  }

  function fmtCount(value) {
    return Math.floor(value || 0).toLocaleString('en-US');
  }

  function getVehicleById(vehicleId) {
    for (var i = 0; i < state.vehicles.length; i++) {
      if (state.vehicles[i].id === vehicleId) {
        return state.vehicles[i];
      }
    }
    return null;
  }

  function buildXpMeta(progression) {
    var levelStart = progression.currentLevelXp || 0;
    var nextLevelXp = progression.nextLevelXp;
    var currentXp = progression.xp || 0;
    var fill = 100;
    var text = 'MAX LEVEL';

    if (nextLevelXp != null) {
      var span = Math.max(1, nextLevelXp - levelStart);
      fill = Math.max(0, Math.min(100, ((currentXp - levelStart) / span) * 100));
      text = fmtCount(currentXp - levelStart) + ' / ' + fmtCount(span) + ' XP';
    }

    return {
      fill: fill,
      text: text,
    };
  }

  function buildPartCards(parts) {
    if (!parts.categories.length) {
      return '<div class="phone-vehicles-empty phone-vehicles-empty--section">No part data synced yet</div>';
    }

    var html = '<div class="phone-vehicles-mod-grid">';
    for (var i = 0; i < parts.categories.length; i++) {
      var item = parts.categories[i];
      var unlocked = item.unlockedOptions.length
        ? escapeHtml(item.unlockedOptions.join(', '))
        : 'None yet';
      var nextUnlock = item.nextUnlock
        ? 'Next unlock: Lv. ' + item.nextUnlock.level + ' ' + escapeHtml(item.nextUnlock.optionName)
        : 'Fully unlocked';

      html += '<div class="phone-vehicles-mod-card" data-mod-name="' + escapeHtml(String(item.modName).toLowerCase()) + '">'
        + '<div class="phone-vehicles-mod-top">'
        + '<span class="phone-vehicles-mod-name">' + escapeHtml(item.modName) + '</span>'
        + '<span class="phone-vehicles-mod-count">' + item.unlockedCount + ' / ' + item.totalCount + '</span>'
        + '</div>'
        + '<div class="phone-vehicles-mod-current">Current: ' + escapeHtml(item.currentOptionName) + '</div>'
        + '<div class="phone-vehicles-mod-unlocked">Unlocked: ' + unlocked + '</div>'
        + '<div class="phone-vehicles-mod-next">' + nextUnlock + '</div>'
        + '</div>';
    }

    html += '</div>';
    return html;
  }

  function buildFutureUnlockCards(items) {
    if (!items.length) {
      return '<div class="phone-vehicles-empty phone-vehicles-empty--section">Nothing else queued</div>';
    }

    var html = '<div class="phone-vehicles-compact-grid">';
    for (var i = 0; i < items.length; i++) {
      var item = items[i];
      html += '<div class="phone-vehicles-future-row">'
        + '<span class="phone-vehicles-future-level">LV ' + item.level + '</span>'
        + '<div class="phone-vehicles-future-copy">'
        + '<span class="phone-vehicles-future-mod">' + escapeHtml(item.modName) + '</span>'
        + '<span class="phone-vehicles-future-option">' + escapeHtml(item.optionName) + '</span>'
        + '</div>'
        + '</div>';
    }

    html += '</div>';
    return html;
  }

  function buildEventRows(items) {
    if (!items.length) {
      return '<div class="phone-vehicles-empty phone-vehicles-empty--section">No recorded event times in this vehicle</div>';
    }

    var html = '<div class="phone-vehicles-event-list">';
    for (var i = 0; i < items.length; i++) {
      var item = items[i];
      var goal = '';
      if (item.goalTime != null) {
        goal = item.passed
          ? '<span class="phone-vehicles-event-goal is-pass">Goal Beat</span>'
          : '<span class="phone-vehicles-event-goal">Goal: ' + formatTime(item.goalTime * 1000) + '</span>';
      }

      html += '<div class="phone-vehicles-event-row">'
        + '<div class="phone-vehicles-event-copy">'
        + '<span class="phone-vehicles-event-name">' + escapeHtml(item.name) + '</span>'
        + goal
        + '</div>'
        + '<span class="phone-vehicles-event-time">' + formatTime(item.score) + '</span>'
        + '</div>';
    }

    html += '</div>';
    return html;
  }

  function renderList() {
    if (!els.list) return;

    if (!state.vehicles.length) {
      els.list.innerHTML = '<div class="phone-vehicles-empty">No owned vehicles yet</div>';
      return;
    }

    var html = '';
    for (var i = 0; i < state.vehicles.length; i++) {
      var vehicle = state.vehicles[i];
      var classes = 'phone-vehicles-list-item';
      if (vehicle.id === state.selectedVehicleId) classes += ' is-selected';
      if (vehicle.id === state.activeVehicleId) classes += ' is-active';

      html += '<button type="button" class="' + classes + '" data-vehicle-id="' + escapeHtml(vehicle.id) + '">'
        + '<div class="phone-vehicles-list-top">'
        + '<span class="phone-vehicles-list-name">' + escapeHtml(vehicle.displayName) + '</span>'
        + '<span class="phone-vehicles-list-level">LV ' + ((vehicle.progression && vehicle.progression.level) || 1) + '</span>'
        + '</div>'
        + '<div class="phone-vehicles-list-meta">'
        + '<span class="phone-vehicles-list-model">' + escapeHtml(vehicle.modelName) + '</span>'
        + (vehicle.id === state.activeVehicleId ? '<span class="phone-vehicles-list-badge">ACTIVE</span>' : '')
        + '</div>'
        + '</button>';
    }

    els.list.innerHTML = html;
  }

  function renderPanel() {
    if (!els.panel) return;

    var vehicle = getVehicleById(state.selectedVehicleId);
    if (!vehicle) {
      els.panel.innerHTML = '<div class="phone-vehicles-empty">Select a vehicle</div>';
      return;
    }

    var progression = vehicle.progression || {};
    var xpMeta = buildXpMeta(progression);
    var totalFutureUnlocks = vehicle.futureVisualUnlocks.length + vehicle.futurePerformanceUnlocks.length;

    els.panel.innerHTML = ''
      + '<div class="phone-vehicles-hero">'
      + '<div class="phone-vehicles-hero-copy">'
      + '<span class="phone-vehicles-eyebrow">' + escapeHtml(vehicle.modelName) + '</span>'
      + '<h2 class="phone-vehicles-name">' + escapeHtml(vehicle.displayName) + '</h2>'
      + '<div class="phone-vehicles-tags">'
      + (vehicle.id === state.activeVehicleId ? '<span class="phone-vehicles-tag is-active">ACTIVE VEHICLE</span>' : '<span class="phone-vehicles-tag">OWNED VEHICLE</span>')
      + '<span class="phone-vehicles-tag">LV ' + (progression.level || 1) + '</span>'
      + '</div>'
      + '</div>'
      + '<div class="phone-vehicles-summary-grid">'
      + '<div class="phone-vehicles-summary-card">'
      + '<span class="phone-vehicles-summary-label">Visual Unlocks</span>'
      + '<span class="phone-vehicles-summary-value">' + vehicle.visualParts.unlockedCount + ' / ' + vehicle.visualParts.totalCount + '</span>'
      + '</div>'
      + '<div class="phone-vehicles-summary-card">'
      + '<span class="phone-vehicles-summary-label">Performance Unlocks</span>'
      + '<span class="phone-vehicles-summary-value">' + vehicle.performanceParts.unlockedCount + ' / ' + vehicle.performanceParts.totalCount + '</span>'
      + '</div>'
      + '<div class="phone-vehicles-summary-card">'
      + '<span class="phone-vehicles-summary-label">Future Unlocks</span>'
      + '<span class="phone-vehicles-summary-value">' + totalFutureUnlocks + '</span>'
      + '</div>'
      + '<div class="phone-vehicles-summary-card">'
      + '<span class="phone-vehicles-summary-label">Event Times</span>'
      + '<span class="phone-vehicles-summary-value">' + vehicle.eventResults.length + '</span>'
      + '</div>'
      + '</div>'
      + '</div>'
      + '<div class="phone-vehicles-section">'
      + '<div class="phone-vehicles-section-head">'
      + '<span class="phone-vehicles-section-title">Progression</span>'
      + '<span class="phone-vehicles-section-stat">Max ' + (progression.maxLevel || 1) + '</span>'
      + '</div>'
      + '<div class="phone-vehicles-progress-card">'
      + '<div class="phone-vehicles-progress-top">'
      + '<span class="phone-vehicles-progress-level">Level ' + (progression.level || 1) + '</span>'
      + '<span class="phone-vehicles-progress-xp">' + escapeHtml(xpMeta.text) + '</span>'
      + '</div>'
      + '<div class="phone-vehicles-progress-bar"><span class="phone-vehicles-progress-fill" style="width:' + xpMeta.fill + '%"></span></div>'
      + '</div>'
      + '</div>'
      + '<div class="phone-vehicles-dashboard">'
      + '<div class="phone-vehicles-main-col">'
      + '<div class="phone-vehicles-search-wrap">'
      + '<svg class="phone-vehicles-search-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>'
      + '<input type="text" class="phone-vehicles-search" placeholder="Search parts" aria-label="Search parts" autocomplete="off" />'
      + '<span class="phone-vehicles-search-empty" hidden>No matching parts</span>'
      + '</div>'
      + '<div class="phone-vehicles-section">'
      + '<div class="phone-vehicles-section-head">'
      + '<span class="phone-vehicles-section-title">Visual Parts</span>'
      + '<span class="phone-vehicles-section-stat">' + vehicle.visualParts.unlockedCount + ' / ' + vehicle.visualParts.totalCount + ' unlocked</span>'
      + '</div>'
      + buildPartCards(vehicle.visualParts)
      + '</div>'
      + '<div class="phone-vehicles-section">'
      + '<div class="phone-vehicles-section-head">'
      + '<span class="phone-vehicles-section-title">Performance Parts</span>'
      + '<span class="phone-vehicles-section-stat">' + vehicle.performanceParts.unlockedCount + ' / ' + vehicle.performanceParts.totalCount + ' unlocked</span>'
      + '</div>'
      + buildPartCards(vehicle.performanceParts)
      + '</div>'
      + '</div>'
      + '<div class="phone-vehicles-side-col">'
      + '<div class="phone-vehicles-section">'
      + '<div class="phone-vehicles-section-head">'
      + '<span class="phone-vehicles-section-title">Next Level Unlocks</span>'
      + '<span class="phone-vehicles-section-stat">' + totalFutureUnlocks + ' pending</span>'
      + '</div>'
      + '<div class="phone-vehicles-next-grid">'
      + '<div class="phone-vehicles-next-card">'
      + '<div class="phone-vehicles-section-head">'
      + '<span class="phone-vehicles-section-title">Visual</span>'
      + '<span class="phone-vehicles-section-stat">' + vehicle.futureVisualUnlocks.length + '</span>'
      + '</div>'
      + buildFutureUnlockCards(vehicle.futureVisualUnlocks)
      + '</div>'
      + '<div class="phone-vehicles-next-card">'
      + '<div class="phone-vehicles-section-head">'
      + '<span class="phone-vehicles-section-title">Performance</span>'
      + '<span class="phone-vehicles-section-stat">' + vehicle.futurePerformanceUnlocks.length + '</span>'
      + '</div>'
      + buildFutureUnlockCards(vehicle.futurePerformanceUnlocks)
      + '</div>'
      + '</div>'
      + '</div>'
      + '<div class="phone-vehicles-section">'
      + '<div class="phone-vehicles-section-head">'
      + '<span class="phone-vehicles-section-title">Event Times</span>'
      + '<span class="phone-vehicles-section-stat">' + vehicle.eventResults.length + ' results</span>'
      + '</div>'
      + buildEventRows(vehicle.eventResults)
      + '</div>'
      + '</div>'
      + '</div>';
  }

  function selectVehicle(vehicleId) {
    state.selectedVehicleId = vehicleId;
    renderList();
    renderPanel();
  }

  function filterParts(query) {
    if (!els.panel) return;
    var q = (query || '').trim().toLowerCase();
    var cards = els.panel.querySelectorAll('.phone-vehicles-mod-card');
    for (var i = 0; i < cards.length; i++) {
      var name = cards[i].getAttribute('data-mod-name') || '';
      cards[i].classList.toggle('is-filtered-out', q !== '' && name.indexOf(q) === -1);
    }

    var grids = els.panel.querySelectorAll('.phone-vehicles-mod-grid');
    var anyVisible = false;
    for (var g = 0; g < grids.length; g++) {
      var visible = grids[g].querySelectorAll('.phone-vehicles-mod-card:not(.is-filtered-out)').length;
      var section = grids[g].closest('.phone-vehicles-section');
      if (section) section.classList.toggle('is-filtered-out', q !== '' && visible === 0);
      if (visible > 0) anyVisible = true;
    }

    var empty = els.panel.querySelector('.phone-vehicles-search-empty');
    if (empty) empty.hidden = !(q !== '' && !anyVisible);
  }

  function loadVehicles() {
    if (!els.list || !els.panel) return;

    els.list.innerHTML = '<div class="phone-vehicles-empty">Loading...</div>';
    els.panel.innerHTML = '<div class="phone-vehicles-empty">Loading vehicle overview...</div>';

    SK.nui.post('phone:vehicles:getData').done(function (data) {
      state.vehicles = data.vehicles || [];
      state.activeVehicleId = data.activeVehicleId || '';
      state.selectedVehicleId = state.activeVehicleId;

      if (!state.selectedVehicleId && state.vehicles.length) {
        state.selectedVehicleId = state.vehicles[0].id;
      }

      renderList();
      renderPanel();
    }).fail(function () {
      state.vehicles = [];
      state.activeVehicleId = '';
      state.selectedVehicleId = '';
      els.list.innerHTML = '<div class="phone-vehicles-empty">Unable to load vehicles</div>';
      els.panel.innerHTML = '<div class="phone-vehicles-empty">Unable to load vehicle overview</div>';
    });
  }

  $(function () {
    resolveEls();

    if (els.list) {
      els.list.addEventListener('click', function (event) {
        var button = event.target.closest('[data-vehicle-id]');
        if (!button) return;

        var vehicleId = button.getAttribute('data-vehicle-id');
        if (!vehicleId || vehicleId === state.selectedVehicleId) return;
        selectVehicle(vehicleId);
      });
    }

    if (els.panel) {
      els.panel.addEventListener('input', function (event) {
        if (event.target && event.target.classList.contains('phone-vehicles-search')) {
          filterParts(event.target.value);
        }
      });
    }
  });

  window.SKPhone.registerApp('Vehicles', function () {
    loadVehicles();
  });

  window.SKPhone.registerControllerAdapter('Vehicles', {
    onAnalogScroll: function (_, lookY) {
      if (!els.panel || Math.abs(lookY) < 0.01) {
        return false;
      }
      els.panel.scrollTop += lookY * 24;
      return true;
    }
  });
})(window);
