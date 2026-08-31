import { useState } from "react";
import { marked } from "marked";
import DOMPurify from "dompurify";
import { api } from "../lib/api";
import type { Note } from "../lib/types";
import "./NoteList.css";

interface NoteListItemProps {
  note: Note;
  onUpdated: (note: Note) => void;
  onDelete: () => void;
}

export function NoteListItem({ note, onUpdated, onDelete }: NoteListItemProps) {
  const [editingTitle, setEditingTitle] = useState(false);
  const [titleDraft, setTitleDraft] = useState(note.title);
  const [mode, setMode] = useState<"edit" | "preview">("edit");
  const [contentDraft, setContentDraft] = useState(note.content);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function patchNote(body: Partial<Pick<Note, "title" | "content">>): Promise<boolean> {
    setSaving(true);
    setError(null);
    try {
      const updated = await api.patch<Note>(`/notes/${note.id}`, body);
      onUpdated(updated);
      return true;
    } catch {
      setError("Не удалось сохранить заметку.");
      return false;
    } finally {
      setSaving(false);
    }
  }

  async function commitTitle() {
    const trimmed = titleDraft.trim();
    if (!trimmed) {
      setTitleDraft(note.title);
      setEditingTitle(false);
      return;
    }
    if (trimmed === note.title) {
      setEditingTitle(false);
      return;
    }
    if (await patchNote({ title: trimmed })) setEditingTitle(false);
  }

  /** Saves the draft if it changed; returns whether it's now safe to leave edit mode. */
  async function commitContent(): Promise<boolean> {
    if (contentDraft === note.content) return true;
    return patchNote({ content: contentDraft });
  }

  async function handleTogglePreview() {
    if (mode === "edit") {
      // Only leave edit mode once the draft is actually saved -- otherwise a
      // failed save would silently swap the textarea for a preview of the
      // *old* content, hiding unsaved text instead of just reporting the error.
      if (await commitContent()) setMode("preview");
    } else {
      setMode("edit");
    }
  }

  // note.content, not contentDraft: the preview always reflects the
  // server-confirmed version, never an unsaved draft (see handleTogglePreview).
  const renderedHtml = DOMPurify.sanitize(marked.parse(note.content, { async: false }));

  return (
    <div className="note-item">
      <div className="note-item__header">
        {editingTitle ? (
          <input
            className="note-item__title-input"
            value={titleDraft}
            autoFocus
            disabled={saving}
            onChange={(event) => setTitleDraft(event.target.value)}
            onBlur={() => void commitTitle()}
            onKeyDown={(event) => {
              if (event.key === "Enter") {
                event.preventDefault();
                void commitTitle();
              }
              if (event.key === "Escape") {
                setTitleDraft(note.title);
                setEditingTitle(false);
              }
            }}
          />
        ) : (
          <h3
            className="note-item__title"
            onClick={() => {
              setTitleDraft(note.title);
              setEditingTitle(true);
            }}
            title="Нажмите, чтобы изменить"
          >
            {note.title}
          </h3>
        )}

        <div className="note-item__actions">
          <button
            type="button"
            className="note-item__mode-btn"
            onClick={() => void handleTogglePreview()}
            disabled={saving}
          >
            {mode === "edit" ? "Просмотр" : "Редактировать"}
          </button>
          <button className="note-item__delete" type="button" onClick={onDelete} aria-label="Удалить заметку">
            ✕
          </button>
        </div>
      </div>

      {mode === "edit" ? (
        <textarea
          className="note-item__content-input"
          value={contentDraft}
          disabled={saving}
          onChange={(event) => setContentDraft(event.target.value)}
          onBlur={() => void commitContent()}
          placeholder="Markdown…"
        />
      ) : (
        <div className="note-item__preview" dangerouslySetInnerHTML={{ __html: renderedHtml }} />
      )}

      {error && <p className="note-item__error">{error}</p>}
    </div>
  );
}
