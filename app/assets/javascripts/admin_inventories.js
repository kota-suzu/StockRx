// 管理者在庫一覧の機能
document.addEventListener('DOMContentLoaded', function() {
  // 全選択機能
  const selectAllCheckbox = document.getElementById('selectAll');
  const inventoryCheckboxes = document.querySelectorAll('.inventory-checkbox');
  const bulkActionsCard = document.getElementById('bulkActionsCard');
  const selectedCountSpan = document.getElementById('selectedCount');
  const clearSelectionBtn = document.getElementById('clearSelectionBtn');

  // 全選択チェックボックスの動作
  if (selectAllCheckbox) {
    selectAllCheckbox.addEventListener('change', function() {
      const isChecked = this.checked;
      
      inventoryCheckboxes.forEach(checkbox => {
        checkbox.checked = isChecked;
      });
      
      updateBulkActions();
    });
  }

  // 個別チェックボックスの動作
  inventoryCheckboxes.forEach(checkbox => {
    checkbox.addEventListener('change', function() {
      updateSelectAllState();
      updateBulkActions();
    });
  });

  // 選択解除ボタン
  if (clearSelectionBtn) {
    clearSelectionBtn.addEventListener('click', function() {
      inventoryCheckboxes.forEach(checkbox => {
        checkbox.checked = false;
      });
      if (selectAllCheckbox) {
        selectAllCheckbox.checked = false;
      }
      updateBulkActions();
    });
  }

  // 全選択チェックボックスの状態を更新
  function updateSelectAllState() {
    if (!selectAllCheckbox) return;

    const checkedCount = document.querySelectorAll('.inventory-checkbox:checked').length;
    const totalCount = inventoryCheckboxes.length;

    if (checkedCount === 0) {
      selectAllCheckbox.checked = false;
      selectAllCheckbox.indeterminate = false;
    } else if (checkedCount === totalCount) {
      selectAllCheckbox.checked = true;
      selectAllCheckbox.indeterminate = false;
    } else {
      selectAllCheckbox.checked = false;
      selectAllCheckbox.indeterminate = true;
    }
  }

  // バルクアクションカードの表示/非表示と選択数の更新
  function updateBulkActions() {
    const checkedCheckboxes = document.querySelectorAll('.inventory-checkbox:checked');
    const checkedCount = checkedCheckboxes.length;

    if (selectedCountSpan) {
      selectedCountSpan.textContent = checkedCount;
    }

    if (bulkActionsCard) {
      if (checkedCount > 0) {
        bulkActionsCard.style.display = 'block';
        bulkActionsCard.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
      } else {
        bulkActionsCard.style.display = 'none';
      }
    }
  }

  // バルクアクションボタンの動作
  const bulkArchiveBtn = document.getElementById('bulkArchiveBtn');
  const bulkActivateBtn = document.getElementById('bulkActivateBtn');
  const bulkDeleteBtn = document.getElementById('bulkDeleteBtn');

  if (bulkArchiveBtn) {
    bulkArchiveBtn.addEventListener('click', function() {
      performBulkAction('archive', '選択した在庫をアーカイブしますか？');
    });
  }

  if (bulkActivateBtn) {
    bulkActivateBtn.addEventListener('click', function() {
      performBulkAction('activate', '選択した在庫を有効化しますか？');
    });
  }

  if (bulkDeleteBtn) {
    bulkDeleteBtn.addEventListener('click', function() {
      performBulkAction('delete', '選択した在庫を削除しますか？この操作は元に戻せません。');
    });
  }

  // バルクアクションの実行
  function performBulkAction(action, confirmMessage) {
    const checkedCheckboxes = document.querySelectorAll('.inventory-checkbox:checked');
    const selectedIds = Array.from(checkedCheckboxes).map(cb => cb.value);

    if (selectedIds.length === 0) {
      alert('操作する在庫を選択してください。');
      return;
    }

    if (!confirm(confirmMessage + `\n\n選択された在庫: ${selectedIds.length}件`)) {
      return;
    }

    // TODO: Ajax でバルクアクションを実行
    console.log(`Bulk ${action} for IDs:`, selectedIds);
    
    // 実装例（実際のエンドポイントに応じて調整が必要）
    /*
    fetch('/admin/inventories/bulk_action', {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      },
      body: JSON.stringify({
        action: action,
        ids: selectedIds
      })
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        // ページをリロードまたはTurbo Frameを更新
        location.reload();
      } else {
        alert('操作に失敗しました: ' + data.message);
      }
    })
    .catch(error => {
      console.error('Error:', error);
      alert('操作中にエラーが発生しました。');
    });
    */
    
    // 暫定的にページリロード
    alert(`${action} アクションが実行されました。（${selectedIds.length}件）`);
  }

  // 初期状態の設定
  updateSelectAllState();
  updateBulkActions();
});

// Turbo Frame 更新時の再初期化
document.addEventListener('turbo:frame-load', function(event) {
  if (event.target.id === 'inventory_list') {
    // フレームが更新された時に再初期化
    setTimeout(() => {
      const script = document.createElement('script');
      script.src = '/assets/admin_inventories.js';
      document.head.appendChild(script);
    }, 100);
  }
});