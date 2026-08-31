// Shapes mirror the backend's Prisma models / route responses exactly
// (see backend/src/routes/projects.ts and backend/src/routes/tasks.ts).
// Dates travel over JSON as ISO strings, not Date objects.

export type TaskStatus = "pending" | "done" | "blocked";

export interface Project {
  id: string;
  name: string;
  archivedAt: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface Task {
  id: string;
  projectId: string;
  title: string;
  description: string | null;
  status: TaskStatus;
  position: number;
  remindAt: string | null;
  createdAt: string;
  updatedAt: string;
  isCurrent: boolean;
}

export interface Note {
  id: string;
  projectId: string;
  title: string;
  content: string;
  createdAt: string;
  updatedAt: string;
}
