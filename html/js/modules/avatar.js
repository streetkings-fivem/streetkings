(function (window) {
  'use strict';

  var SK = window.StreetKings;

  var state = {
    visible: false,
    ui: null,
    activeLeftTab: 'face',
    activeRightTab: 'clothing',
    browse: {
      clothing: {},
      props: {},
    },
    activeCategoryKey: {
      clothing: null,
      props: null,
    },
    // cart maps categoryKey -> { drawable, texture, price, label, kind }
    cart: {},
    drag: { active: false, lastX: 0, lastY: 0 },
  };

  var els = {};

  function isWardrobe() {
    return state.ui && state.ui.mode === 'wardrobe';
  }

  function clone(value) {
    return JSON.parse(JSON.stringify(value));
  }

  function fmtNumber(value) {
    return Math.floor(value).toLocaleString('en-US');
  }

  function fmtCurrency(value) {
    return fmtNumber(value);
  }

  function toast(title, type, duration) {
    window.dispatchEvent(new MessageEvent('message', {
      data: {
        type: 'toast',
        title: title,
        toastType: type || 'info',
        duration: duration || 2500,
      },
    }));
  }

  function toastAvatarActionError(result, categoryLabel) {
    if (!result) {
      toast('Could not apply ' + categoryLabel, 'error', 2800);
      return;
    }

    if (result.error === 'insufficient_funds') {
      toast('Insufficient GearCoins', 'error', 3000);
      return;
    }

    if (result.error === 'not_owned') {
      toast('Variation not owned', 'error', 2800);
      return;
    }

    toast('Could not apply ' + categoryLabel, 'error', 2800);
  }

  function formatLabel(key) {
    return key
      .replace(/([A-Z])/g, ' $1')
      .replace(/_/g, ' ')
      .replace(/\b\w/g, function (match) { return match.toUpperCase(); })
      .replace('Lenght', 'Length');
  }

  function getAppearance() {
    return state.ui.appearance;
  }

  function resolveEls() {
    els.root = document.getElementById('viewAvatar');
    els.balance = document.getElementById('avatarBalance');
    els.balanceWrap = document.getElementById('avatarBalance').parentElement;
    els.cameraHeight = document.getElementById('avatarCameraHeight');
    els.spotlight = document.getElementById('avatarSpotlight');
    els.back = document.getElementById('avatarBack');
    els.title = document.querySelector('.sk-avatar-title');
    els.viewport = document.getElementById('avatarViewport');
    els.gender = document.getElementById('avatarGenderSwitch');
    els.tabs = document.getElementById('avatarTabs');
    els.panelCopy = document.getElementById('avatarPanelCopy');
    els.panelEyebrow = document.getElementById('avatarPanelEyebrow');
    els.panelTitle = document.getElementById('avatarPanelTitle');
    els.panelDescription = document.getElementById('avatarPanelDescription');
    els.controls = document.getElementById('avatarControls');
    els.browseTabs = document.getElementById('avatarBrowseTabs');
    els.browser = document.getElementById('avatarBrowser');
    els.previewEyebrow = document.getElementById('avatarPreviewEyebrow');
    els.previewTitle = document.getElementById('avatarPreviewTitle');
    els.previewCopy = document.getElementById('avatarPreviewCopy');
    els.leftPanel = document.querySelector('.sk-avatar-panel--left');
  }

  function setPreviewText(eyebrow, title, copy) {
    els.previewEyebrow.textContent = eyebrow;
    els.previewTitle.textContent = title;
    els.previewCopy.textContent = copy;
  }

  function setPanelText(eyebrow, title, copy, visible) {
    els.panelCopy.style.display = visible ? '' : 'none';
    if (!visible) return;
    els.panelEyebrow.textContent = eyebrow;
    els.panelTitle.textContent = title;
    els.panelDescription.textContent = copy;
  }

  function setDefaultBrowseText() {
    if (isWardrobe()) {
      setPreviewText('Wardrobe', 'Equip owned clothing', 'Browse your owned clothing and props to change your outfit.');
    } else {
      setPreviewText('Wearables', 'Browse clothing and props', 'Open Clothing or Props on the right to browse owned and purchasable variations.');
    }
  }

  function updateCameraControls() {
    if (!state.ui || !state.ui.camera) return;
    var camera = state.ui.camera;
    var span = Math.max(0.001, camera.maxHeight - camera.minHeight);
    els.cameraHeight.value = String((camera.height - camera.minHeight) / span);
  }

  function applyResult(result) {
    if (!result || !result.ok || !result.state) return;
    state.ui = result.state;
    render();
  }

  function commitAppearance(mutator) {
    var appearance = clone(getAppearance());
    mutator(appearance);
    SK.nui.post('avatar:updateAppearance', { appearance: appearance }).done(function (result) {
      applyResult(result);
    });
  }

  function renderStepper(parent, config) {
    var sliderMin = typeof config.min === 'number' ? config.min
      : typeof config.editMin === 'number' ? config.editMin : 0;
    var sliderMax = typeof config.max === 'number' ? config.max
      : typeof config.editMax === 'number' ? config.editMax : null;
    var useSlider = sliderMax !== null && sliderMax > sliderMin && !config.disabled;

    var row = document.createElement('div');
    row.className = useSlider ? 'sk-avatar-stepper sk-avatar-stepper--slider' : 'sk-avatar-stepper';

    var label = document.createElement('span');
    label.className = 'sk-avatar-stepper-label';
    label.textContent = config.label;

    var value = document.createElement('span');
    value.className = 'sk-avatar-stepper-value';
    value.textContent = config.format ? config.format(config.value) : String(config.value);

    var valueWrap = document.createElement('div');
    valueWrap.className = 'sk-avatar-stepper-value-wrap';
    valueWrap.appendChild(value);

    if (config.editable && !config.disabled) {
      var editor = document.createElement('input');
      editor.type = 'number';
      editor.className = 'sk-avatar-stepper-editor';
      editor.value = String(config.value);
      editor.step = String(config.editStep || config.step || 1);
      if (typeof config.editMin === 'number') editor.min = String(config.editMin);
      if (typeof config.editMax === 'number') editor.max = String(config.editMax);

      var commitEditor = function () {
        if (!config.onEdit) return;
        var next = Number(editor.value);
        if (!Number.isFinite(next)) {
          editor.value = String(config.value);
          return;
        }
        config.onEdit(next);
      };

      valueWrap.addEventListener('click', function () {
        editor.focus();
        editor.select();
      });

      editor.addEventListener('keydown', function (event) {
        if (event.key === 'Enter') {
          event.preventDefault();
          editor.blur();
          return;
        }
        if (event.key === 'Escape') {
          editor.value = String(config.value);
          editor.blur();
        }
      });

      editor.addEventListener('blur', commitEditor);
      valueWrap.appendChild(editor);
    }

    var prev = document.createElement('button');
    prev.type = 'button';
    prev.className = 'sk-avatar-mini-btn sk-avatar-stepper-btn--prev';
    prev.textContent = 'Prev';
    prev.disabled = !!config.disabled;
    prev.addEventListener('click', function () {
      if (config.onStep) {
        config.onStep(-1);
        return;
      }
      config.onChange(config.value - config.step);
    });

    var next = document.createElement('button');
    next.type = 'button';
    next.className = 'sk-avatar-mini-btn sk-avatar-stepper-btn--next';
    next.textContent = 'Next';
    next.disabled = !!config.disabled;
    next.addEventListener('click', function () {
      if (config.onStep) {
        config.onStep(1);
        return;
      }
      config.onChange(config.value + config.step);
    });

    if (useSlider) {
      var range = document.createElement('input');
      range.type = 'range';
      range.className = 'sk-avatar-stepper-range';
      range.min = String(sliderMin);
      range.max = String(sliderMax);
      range.step = String(config.step || 1);
      range.value = String(config.value);

      range.addEventListener('input', function () {
        value.textContent = config.format ? config.format(Number(range.value)) : String(range.value);
      });

      range.addEventListener('change', function () {
        var nextValue = Number(range.value);
        var setAbsolute = config.onEdit || config.onChange;
        if (setAbsolute) setAbsolute(nextValue);
      });

      row.appendChild(label);
      row.appendChild(valueWrap);
      row.appendChild(prev);
      row.appendChild(range);
      row.appendChild(next);
      parent.appendChild(row);
      return;
    }

    var controls = document.createElement('div');
    controls.className = 'sk-avatar-stepper-controls';
    controls.appendChild(prev);
    controls.appendChild(valueWrap);
    controls.appendChild(next);

    row.appendChild(label);
    row.appendChild(controls);
    parent.appendChild(row);
  }

  function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
  }

  function renderSlider(parent, labelText, value, onCommit, options) {
    var opts = options || {};
    var min = typeof opts.min === 'number' ? opts.min : -1;
    var max = typeof opts.max === 'number' ? opts.max : 1;
    var step = typeof opts.step === 'number' ? opts.step : 0.1;

    var wrap = document.createElement('label');
    wrap.className = 'sk-avatar-slider';

    var label = document.createElement('span');
    label.className = 'sk-avatar-slider-label';
    label.textContent = labelText;

    var number = document.createElement('span');
    number.className = 'sk-avatar-slider-value';
    number.textContent = value.toFixed(1);

    var input = document.createElement('input');
    input.type = 'range';
    input.min = min;
    input.max = max;
    input.step = step;
    input.value = value;

    input.addEventListener('input', function () {
      number.textContent = Number(input.value).toFixed(1);
    });

    input.addEventListener('change', function () {
      onCommit(Number(input.value));
    });

    wrap.appendChild(label);
    wrap.appendChild(number);
    wrap.appendChild(input);
    parent.appendChild(wrap);
  }

  function renderSectionTitle(parent, title, subtitle) {
    var head = document.createElement('div');
    head.className = 'sk-avatar-section-head';

    var h = document.createElement('h4');
    h.className = 'sk-avatar-section-title';
    h.textContent = title;

    var p = document.createElement('p');
    p.className = 'sk-avatar-section-sub';
    p.textContent = subtitle;

    head.appendChild(h);
    head.appendChild(p);
    parent.appendChild(head);
  }

  function renderGenderButtons() {
    els.gender.innerHTML = '';

    [
      { key: 'male', label: 'Male' },
      { key: 'female', label: 'Female' },
    ].forEach(function (gender) {
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'sk-avatar-gender-btn';
      if (state.ui.activeGender === gender.key) btn.classList.add('is-active');
      btn.textContent = gender.label;
      btn.addEventListener('click', function () {
        if (state.ui.activeGender === gender.key) return;
        SK.nui.post('avatar:setGender', { gender: gender.key }).done(function (result) {
          applyResult(result);
        });
      });
      els.gender.appendChild(btn);
    });
  }

  function renderTabs() {
    els.tabs.innerHTML = '';

    [
      { key: 'face', label: 'Face' },
      { key: 'features', label: 'Features' },
    ].forEach(function (tab) {
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'sk-avatar-tab-btn';
      if (state.activeLeftTab === tab.key) btn.classList.add('is-active');
      btn.textContent = tab.label;
      btn.addEventListener('click', function () {
        state.activeLeftTab = tab.key;
        renderLeftPanel();
        renderTabs();
      });
      els.tabs.appendChild(btn);
    });
  }

  function renderBrowseTabs() {
    els.browseTabs.innerHTML = '';

    var tabs = [
      { key: 'clothing', label: 'Clothing' },
      { key: 'props', label: 'Props' },
    ];

    if (!isWardrobe()) {
      var cartCount = Object.keys(state.cart).length;
      tabs.push({ key: 'cart', label: cartCount > 0 ? 'Cart (' + cartCount + ')' : 'Cart' });
    }

    tabs.forEach(function (tab) {
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'sk-avatar-tab-btn';
      if (state.activeRightTab === tab.key) btn.classList.add('is-active');
      if (tab.key === 'cart' && Object.keys(state.cart).length > 0) btn.classList.add('sk-avatar-tab-btn--cart-active');
      btn.textContent = tab.label;
      btn.addEventListener('click', function () {
        state.activeRightTab = tab.key;
        renderRightPanel();
        renderBrowseTabs();
      });
      els.browseTabs.appendChild(btn);
    });
  }

  function renderFaceTab() {
    var appearance = getAppearance();
    var root = els.controls;
    root.innerHTML = '';
    setPanelText('Face', 'Shape, skin, and detail', 'Refine the overall look first, then move into individual face features or clothing.', true);

    renderSectionTitle(root, 'Head Blend', 'Shape and skin values are free and shared across saves.');

    renderStepper(root, {
      label: 'Shape First',
      value: appearance.headBlend.shapeFirst,
      step: 1,
      min: 0,
      max: 45,
      onChange: function (next) {
        commitAppearance(function (draft) {
          draft.headBlend.shapeFirst = clamp(next, 0, 45);
        });
      },
    });

    renderStepper(root, {
      label: 'Shape Second',
      value: appearance.headBlend.shapeSecond,
      step: 1,
      min: 0,
      max: 45,
      onChange: function (next) {
        commitAppearance(function (draft) {
          draft.headBlend.shapeSecond = clamp(next, 0, 45);
        });
      },
    });

    renderStepper(root, {
      label: 'Skin First',
      value: appearance.headBlend.skinFirst,
      step: 1,
      min: 0,
      max: 45,
      onChange: function (next) {
        commitAppearance(function (draft) {
          draft.headBlend.skinFirst = clamp(next, 0, 45);
        });
      },
    });

    renderStepper(root, {
      label: 'Skin Second',
      value: appearance.headBlend.skinSecond,
      step: 1,
      min: 0,
      max: 45,
      onChange: function (next) {
        commitAppearance(function (draft) {
          draft.headBlend.skinSecond = clamp(next, 0, 45);
        });
      },
    });

    renderSlider(root, 'Shape Mix', appearance.headBlend.shapeMix, function (next) {
      commitAppearance(function (draft) {
        draft.headBlend.shapeMix = clamp(Number(next.toFixed(1)), 0, 1);
      });
    }, { min: 0, max: 1, step: 0.1 });

    renderSlider(root, 'Skin Mix', appearance.headBlend.skinMix, function (next) {
      commitAppearance(function (draft) {
        draft.headBlend.skinMix = clamp(Number(next.toFixed(1)), 0, 1);
      });
    }, { min: 0, max: 1, step: 0.1 });

    renderSectionTitle(root, 'Hair And Eyes', 'Hair and eye edits are free.');

    renderStepper(root, {
      label: 'Hair Style',
      value: appearance.hair.style,
      step: 1,
      min: 0,
      max: Math.max(0, state.ui.hairStyleCount - 1),
      onChange: function (next) {
        commitAppearance(function (draft) {
          draft.hair.style = clamp(next, 0, Math.max(0, state.ui.hairStyleCount - 1));
          draft.hair.texture = 0;
        });
      },
    });

    renderStepper(root, {
      label: 'Hair Texture',
      value: appearance.hair.texture,
      step: 1,
      min: 0,
      max: Math.max(0, state.ui.hairTextureCount - 1),
      onChange: function (next) {
        commitAppearance(function (draft) {
          draft.hair.texture = clamp(next, 0, Math.max(0, state.ui.hairTextureCount - 1));
        });
      },
    });

    renderStepper(root, {
      label: 'Hair Color',
      value: appearance.hair.color,
      step: 1,
      min: 0,
      max: Math.max(0, state.ui.hairColorCount - 1),
      onChange: function (next) {
        commitAppearance(function (draft) {
          draft.hair.color = clamp(next, 0, Math.max(0, state.ui.hairColorCount - 1));
        });
      },
    });

    renderStepper(root, {
      label: 'Highlight',
      value: appearance.hair.highlight,
      step: 1,
      min: 0,
      max: Math.max(0, state.ui.hairColorCount - 1),
      onChange: function (next) {
        commitAppearance(function (draft) {
          draft.hair.highlight = clamp(next, 0, Math.max(0, state.ui.hairColorCount - 1));
        });
      },
    });

    renderStepper(root, {
      label: 'Eye Color',
      value: appearance.eyeColor,
      step: 1,
      min: 0,
      max: Math.max(0, state.ui.eyeColorCount - 1),
      onChange: function (next) {
        commitAppearance(function (draft) {
          draft.eyeColor = clamp(next, 0, Math.max(0, state.ui.eyeColorCount - 1));
        });
      },
    });

    renderSectionTitle(root, 'Overlays', 'Makeup, facial hair, and skin details are also free.');

    state.ui.headOverlays.forEach(function (overlayMeta) {
      renderStepper(root, {
        label: formatLabel(overlayMeta.key) + ' Style',
        value: appearance.headOverlays[overlayMeta.key].style,
        step: 1,
        min: 0,
        max: Math.max(0, overlayMeta.styleCount - 1),
        onChange: function (next) {
          commitAppearance(function (draft) {
            draft.headOverlays[overlayMeta.key].style = clamp(next, 0, Math.max(0, overlayMeta.styleCount - 1));
          });
        },
      });

      renderSlider(root, formatLabel(overlayMeta.key) + ' Opacity', appearance.headOverlays[overlayMeta.key].opacity, function (next) {
        commitAppearance(function (draft) {
          draft.headOverlays[overlayMeta.key].opacity = clamp(Number(next.toFixed(1)), 0, 1);
        });
      }, { min: 0, max: 1, step: 0.1 });
    });
  }

  function renderFeaturesTab() {
    var appearance = getAppearance();
    var root = els.controls;
    root.innerHTML = '';
    setPanelText('Features', 'Sculpt the face', 'Use the sliders to shape the nose, jaw, cheeks, chin, and other facial proportions.', true);

    renderSectionTitle(root, 'Face Features', 'Each slider is free and saved immediately when you release it.');

    state.ui.faceFeatures.forEach(function (key) {
      renderSlider(root, formatLabel(key), appearance.faceFeatures[key], function (next) {
        commitAppearance(function (draft) {
          draft.faceFeatures[key] = next;
        });
      });
    });
  }

  function browserState(kind, category) {
    var bucket = state.browse[kind];
    if (!bucket[category.key]) {
      bucket[category.key] = {
        drawable: category.drawable,
        texture: category.texture,
        textureCount: category.textureCount,
        owned: category.owned,
        price: category.price,
      };
    }
    return bucket[category.key];
  }

  function hasSpecialNoDrawable(category) {
    return category.key === 'shirts' || category.key === 'tops';
  }

  function specialNoDrawableLabel(category) {
    if (category.key === 'shirts') return 'NO SHIRT';
    if (category.key === 'tops') return 'NO JACKET';
    return 'OFF';
  }

  function drawableSequence(category) {
    var sequence = [];

    if (hasSpecialNoDrawable(category) && category.drawableCount > 15) {
      sequence.push(15);
    }

    for (var drawable = 0; drawable < category.drawableCount; drawable++) {
      if (hasSpecialNoDrawable(category) && drawable === 15) continue;
      sequence.push(drawable);
    }

    return sequence;
  }

  function formatDrawableValue(category, drawable) {
    if (hasSpecialNoDrawable(category) && drawable === 15) {
      return specialNoDrawableLabel(category);
    }
    return drawable < 0 ? 'Off' : String(drawable);
  }

  function stepDrawableValue(category, current, delta) {
    var sequence = drawableSequence(category);
    if (sequence.length === 0) {
      return current;
    }
    var index = sequence.indexOf(current);
    if (index === -1) {
      index = 0;
    }
    var nextIndex = (index + delta) % sequence.length;
    if (nextIndex < 0) {
      nextIndex += sequence.length;
    }
    return sequence[nextIndex];
  }

  function stepTextureValue(current, delta, textureCount) {
    if (textureCount <= 0) {
      return 0;
    }
    var max = textureCount - 1;
    var next = current + delta;
    if (next > max) {
      return 0;
    }
    if (next < 0) {
      return max;
    }
    return next;
  }

  function renderBrowseMessage() {
    els.controls.innerHTML = '';
    els.controls.appendChild(createBrowserNote('Use the browser on the right to preview, equip, and buy variations in this category.'));
  }

  function createBrowserNote(text) {
    var box = document.createElement('div');
    box.className = 'sk-avatar-note';
    box.textContent = text;
    return box;
  }

  function setActiveCategory(kind, categories) {
    var current = state.activeCategoryKey[kind];
    if (current) {
      for (var i = 0; i < categories.length; i++) {
        if (categories[i].key === current) return current;
      }
    }
    state.activeCategoryKey[kind] = categories.length ? categories[0].key : null;
    return state.activeCategoryKey[kind];
  }

  function selectedCategory(kind, categories) {
    var key = setActiveCategory(kind, categories);
    for (var i = 0; i < categories.length; i++) {
      if (categories[i].key === key) return categories[i];
    }
    return null;
  }

  function previewCategory(kind, category, nextDrawable, nextTexture) {
    SK.nui.post('avatar:previewVariation', {
      categoryKey: category.key,
      drawable: nextDrawable,
      texture: nextTexture,
    }).done(function (result) {
      if (!result || !result.ok) return;
      var selection = browserState(kind, category);
      selection.drawable = result.drawable;
      selection.texture = result.texture;
      selection.textureCount = result.textureCount;
      selection.owned = result.owned;
      selection.price = result.price;
      render();
    });
  }

  function renderCategoryBrowser(kind, categories) {
    els.browser.innerHTML = '';

    var category = selectedCategory(kind, categories);
    if (!category) {
      els.browser.textContent = 'No categories available.';
      return;
    }

    var pillWrap = document.createElement('div');
    pillWrap.className = 'sk-avatar-category-list';

    categories.forEach(function (entry) {
      var pill = document.createElement('button');
      pill.type = 'button';
      pill.className = 'sk-avatar-category-pill';
      if (entry.key === category.key) pill.classList.add('is-active');
      pill.textContent = entry.label;
      pill.addEventListener('click', function () {
        state.activeCategoryKey[kind] = entry.key;
        var selection = browserState(kind, entry);
        previewCategory(kind, entry, selection.drawable, selection.texture);
      });
      pillWrap.appendChild(pill);
    });

    var selection = browserState(kind, category);

    var card = document.createElement('div');
    card.className = 'sk-avatar-browser-card';

    var title = document.createElement('h4');
    title.className = 'sk-avatar-browser-title';
    title.textContent = category.label;

    var meta = document.createElement('p');
    meta.className = 'sk-avatar-browser-meta';
    if (isWardrobe()) {
      meta.textContent = selection.owned
        ? 'Owned variation ready to equip.'
        : 'Not owned. Visit a clothing store to purchase.';
    } else {
      meta.textContent = selection.owned
        ? 'Owned variation ready to equip.'
        : 'Costs ' + fmtCurrency(selection.price) + ' GearCoins.';
    }

    card.appendChild(title);
    card.appendChild(meta);

    renderStepper(card, {
      label: 'Drawable',
      value: selection.drawable,
      step: 1,
      editable: true,
      editStep: 1,
      editMin: kind === 'props' ? -1 : 0,
      editMax: Math.max(0, category.drawableCount - 1),
      format: function (value) { return formatDrawableValue(category, value); },
      onStep: function (delta) {
        var nextDrawable = stepDrawableValue(category, selection.drawable, delta);
        previewCategory(kind, category, nextDrawable, nextDrawable === -1 ? 0 : selection.texture);
      },
      onEdit: function (next) {
        var parsed = Math.floor(next);
        if (kind === 'props') {
          parsed = clamp(parsed, -1, Math.max(0, category.drawableCount - 1));
        } else {
          parsed = clamp(parsed, 0, Math.max(0, category.drawableCount - 1));
        }
        previewCategory(kind, category, parsed, parsed === -1 ? 0 : selection.texture);
      },
    });

    renderStepper(card, {
      label: 'Texture',
      value: selection.texture,
      step: 1,
      format: function (value) { return value < 0 ? 'Off' : String(value); },
      disabled: selection.drawable === -1,
      editable: true,
      editStep: 1,
      editMin: 0,
      editMax: Math.max(0, selection.textureCount - 1),
      onStep: function (delta) {
        var nextTexture = stepTextureValue(selection.texture, delta, selection.textureCount);
        previewCategory(kind, category, selection.drawable, nextTexture);
      },
      onEdit: function (next) {
        var parsed = Math.floor(next);
        if (selection.textureCount <= 0) {
          parsed = 0;
        } else {
          parsed = clamp(parsed, 0, selection.textureCount - 1);
        }
        previewCategory(kind, category, selection.drawable, parsed);
      },
    });

    var actionRow = document.createElement('div');
    actionRow.className = 'sk-avatar-browser-actions';

    var wardrobe = isWardrobe();

    if (wardrobe && !selection.owned) {
      var notOwned = document.createElement('span');
      notOwned.className = 'sk-avatar-browser-locked';
      notOwned.textContent = 'Not Owned';
      actionRow.appendChild(notOwned);
    } else if (selection.owned || wardrobe) {
      // Equip owned directly
      var action = document.createElement('button');
      action.type = 'button';
      action.className = 'sk-avatar-action-btn';
      action.textContent = 'Equip Owned';
      action.addEventListener('click', function () {
        SK.nui.post('avatar:equipOwnedVariation', {
          categoryKey: category.key,
          drawable: selection.drawable,
          texture: selection.texture,
        }).done(function (result) {
          if (!result || !result.ok) {
            toastAvatarActionError(result, category.label);
            return;
          }
          toast('Equipped owned ' + category.label, 'success', 2200);
          if (result && result.ok && state.browse[kind] && state.browse[kind][category.key]) {
            delete state.browse[kind][category.key];
          }
          // Remove from cart if it was there
          delete state.cart[category.key];
          applyResult(result);
        });
      });
      actionRow.appendChild(action);
    } else {
      // Unowned: show cart controls
      var inCart = !!state.cart[category.key]
        && state.cart[category.key].drawable === selection.drawable
        && state.cart[category.key].texture  === selection.texture;

      if (inCart) {
        var inCartLabel = document.createElement('span');
        inCartLabel.className = 'sk-avatar-in-cart-label';
        inCartLabel.textContent = '✓ In Cart';

        var removeBtn = document.createElement('button');
        removeBtn.type = 'button';
        removeBtn.className = 'sk-avatar-action-btn sk-avatar-action-btn--remove';
        removeBtn.textContent = 'Remove';
        removeBtn.addEventListener('click', function () {
          delete state.cart[category.key];
          SK.nui.post('avatar:resetCategoryPreview', { categoryKey: category.key });
          render();
        });

        actionRow.appendChild(inCartLabel);
        actionRow.appendChild(removeBtn);
      } else {
        var addBtn = document.createElement('button');
        addBtn.type = 'button';
        addBtn.className = 'sk-avatar-action-btn sk-avatar-action-btn--add-cart';
        addBtn.textContent = 'Add to Cart  –  ' + fmtCurrency(selection.price) + ' GC';
        addBtn.addEventListener('click', function () {
          state.cart[category.key] = {
            drawable: selection.drawable,
            texture: selection.texture,
            price: selection.price,
            label: category.label,
            kind: kind,
          };
          render();
        });
        actionRow.appendChild(addBtn);
      }
    }
    card.appendChild(actionRow);

    els.browser.appendChild(pillWrap);
    els.browser.appendChild(card);

    setPreviewText(
      kind === 'clothing' ? 'Clothing' : 'Props',
      category.label,
      selection.owned
        ? 'Preview owned variations and equip them instantly.'
        : isWardrobe()
          ? 'Visit a clothing store to purchase this variation.'
          : 'Browse the current category, preview a variation, then buy it once to keep it forever.'
    );
  }

  function renderCartTab() {
    els.browser.innerHTML = '';

    var cartKeys = Object.keys(state.cart);

    setPreviewText('Cart', cartKeys.length + ' item' + (cartKeys.length !== 1 ? 's' : ''), 'Review your outfit and purchase everything at once.');

    if (cartKeys.length === 0) {
      var empty = document.createElement('div');
      empty.className = 'sk-avatar-cart-empty';
      empty.textContent = 'Your cart is empty. Browse Clothing or Props and add items to build an outfit.';
      els.browser.appendChild(empty);
      return;
    }

    var total = 0;
    cartKeys.forEach(function (key) { total += state.cart[key].price; });

    var list = document.createElement('div');
    list.className = 'sk-avatar-cart-list';

    cartKeys.forEach(function (key) {
      var item = state.cart[key];
      var row = document.createElement('div');
      row.className = 'sk-avatar-cart-item';

      var info = document.createElement('div');
      info.className = 'sk-avatar-cart-item-info';

      var label = document.createElement('span');
      label.className = 'sk-avatar-cart-item-label';
      label.textContent = item.label;

      var sub = document.createElement('span');
      sub.className = 'sk-avatar-cart-item-sub';
      sub.textContent = 'Drawable ' + item.drawable + ' · Texture ' + item.texture;

      info.appendChild(label);
      info.appendChild(sub);

      var price = document.createElement('span');
      price.className = 'sk-avatar-cart-item-price';
      price.textContent = fmtCurrency(item.price) + ' GC';

      var removeBtn = document.createElement('button');
      removeBtn.type = 'button';
      removeBtn.className = 'sk-avatar-cart-remove-btn';
      removeBtn.textContent = '×';
      removeBtn.title = 'Remove ' + item.label;
      removeBtn.addEventListener('click', (function (capturedKey) {
        return function () {
          delete state.cart[capturedKey];
          SK.nui.post('avatar:resetCategoryPreview', { categoryKey: capturedKey });
          render();
        };
      })(key));

      row.appendChild(info);
      row.appendChild(price);
      row.appendChild(removeBtn);
      list.appendChild(row);
    });

    var totalRow = document.createElement('div');
    totalRow.className = 'sk-avatar-cart-total';

    var totalLabel = document.createElement('span');
    totalLabel.className = 'sk-avatar-cart-total-label';
    totalLabel.textContent = 'Total';

    var totalValue = document.createElement('span');
    totalValue.className = 'sk-avatar-cart-total-value';
    totalValue.textContent = fmtCurrency(total) + ' GearCoins';

    totalRow.appendChild(totalLabel);
    totalRow.appendChild(totalValue);

    var buyBtn = document.createElement('button');
    buyBtn.type = 'button';
    buyBtn.className = 'sk-avatar-action-btn sk-avatar-cart-buy-btn';
    buyBtn.textContent = 'Buy All  –  ' + fmtCurrency(total) + ' GC';

    var canAfford = state.ui && state.ui.cosmeticCurrency >= total;
    if (!canAfford) {
      buyBtn.disabled = true;
      buyBtn.title = 'Not enough GearCoins';
    }

    buyBtn.addEventListener('click', function () {
      if (buyBtn.disabled) return;
      var items = cartKeys.map(function (key) {
        return {
          categoryKey: key,
          drawable: state.cart[key].drawable,
          texture: state.cart[key].texture,
        };
      });
      buyBtn.disabled = true;
      buyBtn.textContent = 'Purchasing…';
      SK.nui.post('avatar:purchaseCart', { items: items }).done(function (result) {
        if (!result || !result.ok) {
          toastAvatarActionError(result, 'outfit');
          buyBtn.disabled = false;
          buyBtn.textContent = 'Buy All  –  ' + fmtCurrency(total) + ' GC';
          return;
        }
        var count = result.purchasedCount || 0;
        toast('Purchased ' + count + ' item' + (count !== 1 ? 's' : ''), 'success', 2800);
        state.cart = {};
        state.browse.clothing = {};
        state.browse.props = {};
        applyResult(result);
      });
    });

    els.browser.appendChild(list);
    els.browser.appendChild(totalRow);
    els.browser.appendChild(buyBtn);
  }

  function renderWardrobePanel() {
    els.panelCopy.style.display = 'none';
    els.controls.innerHTML = '';

    var wrap = document.createElement('div');
    wrap.className = 'sk-avatar-wardrobe-info';

    var body = document.createElement('p');
    body.className = 'sk-avatar-wardrobe-body';
    body.textContent = 'Equip owned clothing and props. See something you don\u2019t own yet? Pick it up at a clothing store.';

    wrap.appendChild(body);
    els.controls.appendChild(wrap);
  }

  function renderLeftPanel() {
    if (state.activeLeftTab === 'face') {
      renderFaceTab();
      return;
    }
    renderFeaturesTab();
  }

  function renderRightPanel() {
    if (state.activeRightTab === 'cart') {
      renderCartTab();
      return;
    }
    if (state.activeRightTab === 'clothing') {
      renderCategoryBrowser('clothing', state.ui.clothingCategories);
      return;
    }
    renderCategoryBrowser('props', state.ui.propCategories);
  }

  function render() {
    if (!state.visible || !state.ui) return;

    var wardrobe = isWardrobe();

    els.balance.parentElement.style.display = wardrobe ? 'none' : '';
    els.gender.style.display = wardrobe ? 'none' : '';
    els.tabs.style.display = wardrobe ? 'none' : '';

    if (wardrobe) {
      renderWardrobePanel();
    } else {
      els.balance.textContent = fmtCurrency(state.ui.cosmeticCurrency);
    }
    updateCameraControls();
    if (!wardrobe) {
      renderGenderButtons();
      renderTabs();
      renderLeftPanel();
    }
    renderBrowseTabs();
    renderRightPanel();
  }

  function openAvatar(data) {
    state.visible = true;
    state.ui = data.state;
    var wardrobe = isWardrobe();
    els.title.textContent = wardrobe ? 'Wardrobe' : 'Customize Avatar';
    els.root.classList.toggle('sk-avatar--wardrobe', wardrobe);
    els.root.style.display = '';
    render();
  }

  function closeAvatar() {
    state.visible = false;
    state.ui = null;
    state.drag.active = false;
    state.activeLeftTab = 'face';
    state.activeRightTab = 'clothing';
    state.browse.clothing = {};
    state.browse.props = {};
    state.activeCategoryKey.clothing = null;
    state.activeCategoryKey.props = null;
    state.cart = {};
    var modal = document.getElementById('avatarExitModal');
    if (modal) modal.remove();
    els.root.style.display = 'none';
    els.root.classList.remove('sk-avatar--wardrobe');
    els.controls.innerHTML = '';
    els.browseTabs.innerHTML = '';
    els.browser.innerHTML = '';
    els.spotlight.classList.remove('is-active');
  }

  function onViewportMouseDown(e) {
    if (e.button !== 0 || !state.visible) return;
    if (document.getElementById('avatarExitModal')) return;
    state.drag.active = true;
    state.drag.lastX = e.clientX;
    state.drag.lastY = e.clientY;
  }

  function onMouseMove(e) {
    if (!state.drag.active || !state.visible) return;
    if (document.getElementById('avatarExitModal')) {
      state.drag.active = false;
      return;
    }
    var dx = e.clientX - state.drag.lastX;
    var dy = e.clientY - state.drag.lastY;
    state.drag.lastX = e.clientX;
    state.drag.lastY = e.clientY;
    SK.nui.post('avatar:cameraRotate', { dx: dx, dy: dy });
  }

  function onMouseUp() {
    state.drag.active = false;
  }

  function onViewportWheel(e) {
    if (!state.visible) return;
    e.preventDefault();
    SK.nui.post('avatar:cameraZoom', {
      delta: e.deltaY > 0 ? 0.16 : -0.16,
    }).done(function (result) {
      applyResult(result);
    });
  }

  function tryExit() {
    var cartKeys = Object.keys(state.cart);

    if (!isWardrobe() && cartKeys.length > 0) {
      // Remove any existing modal first
      var existing = document.getElementById('avatarExitModal');
      if (existing) existing.remove();

      var modal = document.createElement('div');
      modal.id = 'avatarExitModal';
      modal.className = 'sk-avatar-exit-modal';

      var box = document.createElement('div');
      box.className = 'sk-avatar-exit-modal-box';

      var title = document.createElement('h3');
      title.className = 'sk-avatar-exit-modal-title';
      title.textContent = 'Leave without buying?';

      var body = document.createElement('p');
      body.className = 'sk-avatar-exit-modal-body';
      body.textContent = 'You have ' + cartKeys.length + ' item' + (cartKeys.length !== 1 ? 's' : '') + ' in your cart. Abandon them or go to checkout first?';

      var actions = document.createElement('div');
      actions.className = 'sk-avatar-exit-modal-actions';

      var abandonBtn = document.createElement('button');
      abandonBtn.type = 'button';
      abandonBtn.className = 'sk-avatar-exit-modal-btn sk-avatar-exit-modal-btn--abandon';
      abandonBtn.textContent = 'Leave Anyway';
      abandonBtn.addEventListener('click', function () {
        modal.remove();
        SK.nui.post('avatar:exit', {});
      });

      var checkoutBtn = document.createElement('button');
      checkoutBtn.type = 'button';
      checkoutBtn.className = 'sk-avatar-exit-modal-btn sk-avatar-exit-modal-btn--checkout';
      checkoutBtn.textContent = 'Go to Cart';
      checkoutBtn.addEventListener('click', function () {
        modal.remove();
        state.activeRightTab = 'cart';
        renderRightPanel();
        renderBrowseTabs();
      });

      var stayBtn = document.createElement('button');
      stayBtn.type = 'button';
      stayBtn.className = 'sk-avatar-exit-modal-btn sk-avatar-exit-modal-btn--stay';
      stayBtn.textContent = 'Keep Browsing';
      stayBtn.addEventListener('click', function () {
        modal.remove();
      });

      actions.appendChild(abandonBtn);
      actions.appendChild(checkoutBtn);
      actions.appendChild(stayBtn);
      box.appendChild(title);
      box.appendChild(body);
      box.appendChild(actions);
      modal.appendChild(box);
      document.getElementById('viewAvatar').appendChild(modal);
      return;
    }

    SK.nui.post('avatar:exit', {});
  }

  $(function () {
    resolveEls();

    els.viewport.addEventListener('mousedown', onViewportMouseDown);
    els.viewport.addEventListener('wheel', onViewportWheel, { passive: false });
    document.addEventListener('mousemove', onMouseMove);
    document.addEventListener('mouseup', onMouseUp);

    els.cameraHeight.addEventListener('input', function () {
      if (!state.visible || !state.ui || !state.ui.camera) return;
      var camera = state.ui.camera;
      var value = camera.minHeight + (camera.maxHeight - camera.minHeight) * Number(els.cameraHeight.value);
      SK.nui.post('avatar:setCameraHeight', { height: value }).done(function (result) {
        applyResult(result);
      });
    });

    els.back.addEventListener('click', function () {
      tryExit();
    });

    els.spotlight.addEventListener('click', function () {
      var isActive = els.spotlight.classList.toggle('is-active');
      SK.nui.post('avatar:toggleSpotlight', { enabled: isActive });
    });

    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && state.visible) {
        // If the exit modal is already open, Escape closes it (stay)
        var existing = document.getElementById('avatarExitModal');
        if (existing) {
          existing.remove();
          return;
        }
        tryExit();
      }
    });
  });

  window.addEventListener('message', function (e) {
    var data = e.data;
    if (!data) return;
    if (data.type === 'avatar:open' || data.type === 'avatar:sync') openAvatar(data);
    if (data.type === 'avatar:close') closeAvatar();
  });
})(window);
