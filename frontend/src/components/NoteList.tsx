import { useState, type FormEvent } from "react";
import { api } from "../lib/api";
import type { Note } from "../lib/types";
import { NoteListItem } from "./NoteListItem";
import "./NoteList.css";

interface NoteListProps {
  projectId: string;
  notes: Note[];
  onNotesChange: (notes: Note[]) => void;
}

export function NoteList({ projectId, notes, onNotesChange }: NoteListProps) {
  const [newTitle, setNewTitle] = useState("");
  const [adding, setAdding] = useState(false);
  const [addError, setAddError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  async function handleAdd(event: FormEvent) {
    event.preventDefault();
    const title = newTitle.trim();
    if (!title) return;
    setAdding(true);
    setAddError(null);
    try {
      const note = await api.post<Note>(`/projects/${projectId}/notes`, { title });
      onNotesChange([...notes, note]);
      setNewTitle("");
    } catch {
      setAddError("Не удалось создать заметку.");
    } finally {
      setAdding(false);
    }
  }

  function handleUpdated(updated: Note) {
    onNotesChange(notes.map((note) => (note.id === updated.id ? updated : note)));
  }

  async function handleDelete(noteId: string) {
    if (!window.confirm("Удалить заметку без возможности восстановления?")) return;
    try {
      await api.delete(`/notes/${noteId}`);
      onNotesChange(notes.filter((note) => note.id !== noteId));
    } catch {
      setActionError("Не удалось удалить заметку.");
    }
  }

  return (
    <div className="note-list">
      <form className="note-list__add" onSubmit={(event) => void handleAdd(event)}>
        <input
          type="text"
          placeholder="Новая заметка…"
          value={newTitle}
          onChange={(event) => setNewTitle(event.target.value)}
          disabled={adding}
        />
        <button type="submit" disabled={adding || !newTitle.trim()}>
          Добавить
        </button>
      </form>

      {addError && <p className="note-list__error">{addError}</p>}
      {actionError && <p className="note-list__error">{actionError}</p>}

      {notes.length === 0 ? (
        <p className="note-list__empty">Заметок пока нет.</p>
      ) : (
        <div className="note-list__items">
          {notes.map((note) => (
            <NoteListItem
              key={note.id}
              note={note}
              onUpdated={handleUpdated}
              onDelete={() => void handleDelete(note.id)}
            />
          ))}
        </div>
      )}
    </div>
  );
}
