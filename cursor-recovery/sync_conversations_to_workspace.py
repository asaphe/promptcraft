#!/usr/bin/env python3
"""
Sync all conversations from global storage to a workspace.

PROBLEM: Conversations are stored globally but each workspace maintains
its own list in composer.composerData.allComposers. When you open a new
workspace, it starts empty, so you don't see your history.

SOLUTION: Copy all conversation metadata from global storage into the
workspace's allComposers list so they become visible.

USAGE:
    1. Close Cursor: killall Cursor
    2. Run: python3 sync_conversations_to_workspace.py [workspace_hash]
       (If no workspace_hash provided, uses most recent workspace)
    3. Reopen Cursor and your workspace
"""

import sqlite3
import json
import sys
import subprocess
import shutil
import os
from pathlib import Path
from datetime import datetime


def check_cursor_running():
    """Check if Cursor is running."""
    try:
        result = subprocess.run(['pgrep', '-x', 'Cursor'], capture_output=True, text=True)
        return result.returncode == 0
    except Exception:
        return False


def create_backup(db_path):
    """Create timestamped backup."""
    backup_dir = Path.home() / 'cursor-conversation-history' / 'backups'
    backup_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    backup_path = backup_dir / f'workspace_state.link_convs_{timestamp}.vscdb'

    print(f'Creating backup: {backup_path}')
    shutil.copy2(db_path, backup_path)

    if Path(db_path).stat().st_size != backup_path.stat().st_size:
        print('❌ Backup verification failed!')
        sys.exit(1)

    print(f'✅ Backup created: {backup_path.stat().st_size:,} bytes')
    return backup_path


def get_conversation_metadata(global_conn, conv_id):
    """Extract metadata from a conversation in global storage."""
    cursor = global_conn.cursor()

    cursor.execute("SELECT value FROM cursorDiskKV WHERE key = ?", (f'composerData:{conv_id}',))
    result = cursor.fetchone()

    if not result:
        return None

    try:
        if isinstance(result[0], bytes):
            data = json.loads(result[0].decode('utf-8'))
        else:
            data = json.loads(result[0])
    except:
        return None

    # Extract metadata
    metadata = {
        'type': 'head',
        'composerId': conv_id,
        'createdAt': data.get('createdAt', 0),
        'lastUpdatedAt': data.get('createdAt', 0),  # Use createdAt if no lastUpdatedAt
        'unifiedMode': data.get('unifiedMode', 'agent'),
        'forceMode': data.get('forceMode', 'edit'),
        'hasUnreadMessages': False,
        'totalLinesAdded': 0,
        'totalLinesRemoved': 0,
        'filesChangedCount': 0,
        'isArchived': False,
        'isDraft': False,
        'isWorktree': False,
        'isSpec': False,
        'isBestOfNSubcomposer': False,
        'numSubComposers': 0,
        'referencedPlans': []
    }

    # Try to extract name from conversation text or context
    if 'text' in data and data['text']:
        # Use first few words as name
        first_line = data['text'].split('\n')[0][:60]
        if first_line.strip():
            metadata['name'] = first_line.strip()

    if not metadata.get('name'):
        metadata['name'] = f"Conversation {conv_id[:8]}"

    return metadata


def sync_conversations_to_workspace(workspace_hash=None):
    """Sync all conversations to a workspace."""
    print('='*70)
    print('SYNC CONVERSATIONS TO WORKSPACE')
    print('='*70)

    # Check Cursor is closed
    if check_cursor_running():
        print('\n⚠️  WARNING: Cursor is running!')
        print('Close Cursor first for safety: killall Cursor')
        response = input('Continue anyway? (yes/no): ').strip().lower()
        if response != 'yes':
            print('\n❌ Cancelled')
            sys.exit(0)

    # Find workspace
    workspace_storage = Path.home() / 'Library' / 'Application Support' / 'Cursor' / 'User' / 'workspaceStorage'

    if not workspace_storage.exists():
        print(f'\n❌ Workspace storage not found: {workspace_storage}')
        sys.exit(1)

    # Get workspace directories
    workspace_dirs = sorted(
        [d for d in os.listdir(workspace_storage) if os.path.isdir(os.path.join(workspace_storage, d))],
        key=lambda x: os.path.getmtime(os.path.join(workspace_storage, x)),
        reverse=True
    )

    if workspace_hash:
        target_ws = workspace_hash
        if target_ws not in workspace_dirs:
            print(f'\n❌ Workspace not found: {workspace_hash}')
            print(f'Available workspaces (first 5):')
            for ws in workspace_dirs[:5]:
                print(f'  - {ws}')
            sys.exit(1)
    else:
        target_ws = workspace_dirs[0]
        print(f'\n✅ Using most recent workspace: {target_ws[:16]}...')

    workspace_db = workspace_storage / target_ws / 'state.vscdb'

    if not workspace_db.exists():
        print(f'\n❌ Workspace database not found: {workspace_db}')
        sys.exit(1)

    print(f'✅ Workspace database found')

    # Create backup
    backup_path = create_backup(workspace_db)

    # Open databases
    global_db = Path.home() / 'Library' / 'Application Support' / 'Cursor' / 'User' / 'globalStorage' / 'state.vscdb'

    if not global_db.exists():
        print(f'\n❌ Global database not found: {global_db}')
        sys.exit(1)

    global_conn = sqlite3.connect(global_db)
    ws_conn = sqlite3.connect(workspace_db)

    try:
        # Get all conversation IDs from global storage
        print('\n📊 Getting conversations from global storage...')

        # Option 1: Use lastOpenedBcIds (conversations you've actually opened)
        g_cursor = global_conn.cursor()
        g_cursor.execute("SELECT value FROM ItemTable WHERE key = 'workbench.backgroundComposer.persistentData'")
        g_result = g_cursor.fetchone()

        conv_ids = []
        if g_result:
            if isinstance(g_result[0], bytes):
                g_data = json.loads(g_result[0].decode('utf-8'))
            else:
                g_data = json.loads(g_result[0])

            conv_ids = g_data.get('lastOpenedBcIds', [])
            print(f'  Found {len(conv_ids)} conversations in lastOpenedBcIds')

        # Option 2: If we want ALL conversations, get them from cursorDiskKV
        if not conv_ids or len(conv_ids) < 100:
            g_cursor.execute("SELECT key FROM cursorDiskKV WHERE key LIKE 'composerData:%'")
            all_keys = g_cursor.fetchall()
            conv_ids = [row[0].replace('composerData:', '') for row in all_keys]
            print(f'  Found {len(conv_ids)} total conversations in global storage')

        print(f'\n✅ Total conversations to sync: {len(conv_ids)}')

        # Get existing conversations in workspace
        ws_cursor = ws_conn.cursor()
        ws_cursor.execute("SELECT value FROM ItemTable WHERE key = 'composer.composerData'")
        ws_result = ws_cursor.fetchone()

        existing_composer_data = {}
        existing_conv_ids = set()

        if ws_result:
            if isinstance(ws_result[0], bytes):
                existing_composer_data = json.loads(ws_result[0].decode('utf-8'))
            else:
                existing_composer_data = json.loads(ws_result[0])

            existing_all_composers = existing_composer_data.get('allComposers', [])
            existing_conv_ids = {c.get('composerId') for c in existing_all_composers if isinstance(c, dict) and 'composerId' in c}
            print(f'\n📊 Existing conversations in workspace: {len(existing_conv_ids)}')

        # Build metadata for all conversations
        print(f'\n🔄 Building conversation metadata...')
        new_conversations = []
        skipped = 0

        for i, conv_id in enumerate(conv_ids):
            if i % 500 == 0 and i > 0:
                print(f'  Progress: {i}/{len(conv_ids)}...')

            # Skip if already exists
            if conv_id in existing_conv_ids:
                skipped += 1
                continue

            metadata = get_conversation_metadata(global_conn, conv_id)
            if metadata:
                new_conversations.append(metadata)

        print(f'\n✅ Built metadata for {len(new_conversations)} new conversations')
        print(f'   Skipped {skipped} already existing')

        if not new_conversations:
            print('\n✅ All conversations already synced!')
            ws_conn.close()
            global_conn.close()
            return

        # Merge with existing
        all_conversations = existing_composer_data.get('allComposers', []) + new_conversations

        # Sort by createdAt (newest first)
        all_conversations.sort(key=lambda x: x.get('createdAt', 0) or 0, reverse=True)

        # Update workspace data
        existing_composer_data['allComposers'] = all_conversations

        # Save
        new_value = json.dumps(existing_composer_data)
        ws_cursor.execute(
            "UPDATE ItemTable SET value = ? WHERE key = 'composer.composerData'",
            (new_value,)
        )

        ws_conn.commit()

        # Verify
        ws_cursor.execute("SELECT value FROM ItemTable WHERE key = 'composer.composerData'")
        verify_result = ws_cursor.fetchone()
        if verify_result:
            if isinstance(verify_result[0], bytes):
                verify_data = json.loads(verify_result[0].decode('utf-8'))
            else:
                verify_data = json.loads(verify_result[0])
            verify_count = len(verify_data.get('allComposers', []))
            print(f'\n✅ Synced {len(new_conversations)} conversations')
            print(f'   Total conversations in workspace: {verify_count}')

        ws_conn.close()
        global_conn.close()

        print('\n✅ SUCCESS! Conversations synced to workspace!')
        print('\nWhat was done:')
        print(f'  ✅ Added {len(new_conversations)} conversations to workspace')
        print(f'  ✅ Total conversations now: {verify_count}')
        print('\nNext steps:')
        print('  1. Open Cursor')
        print('  2. Open your workspace')
        print('  3. Check chat history sidebar - conversations should be visible!')
        print('\nIf issues occur, restore backup:')
        print(f'     cp "{backup_path}" "{workspace_db}"')

    except Exception as e:
        print(f'\n❌ Error: {e}')
        import traceback
        traceback.print_exc()
        ws_conn.close()
        global_conn.close()

        print('\nRestoring from backup...')
        shutil.copy2(backup_path, workspace_db)
        print('✅ Backup restored')
        sys.exit(1)


if __name__ == '__main__':
    workspace_hash = sys.argv[1] if len(sys.argv) > 1 else None
    try:
        sync_conversations_to_workspace(workspace_hash)
    except KeyboardInterrupt:
        print('\n\n❌ Interrupted')
        sys.exit(1)
