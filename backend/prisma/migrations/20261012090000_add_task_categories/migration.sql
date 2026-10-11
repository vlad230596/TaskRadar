-- Task categories: groups of tasks inside one project.
--
-- Each project has its own list (`task_categories.projectId`, cascading with
-- the project). A task belongs to at most one (`tasks.categoryId`, nullable);
-- deleting a category leaves its tasks in place, ungrouped (SET NULL).
-- Nothing is backfilled: every existing task starts "без категории".

-- AlterTable
ALTER TABLE "tasks" ADD COLUMN     "categoryId" TEXT;

-- CreateTable
CREATE TABLE "task_categories" (
    "id" TEXT NOT NULL,
    "projectId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "position" DOUBLE PRECISION NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "task_categories_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "task_categories_projectId_position_idx" ON "task_categories"("projectId", "position");

-- CreateIndex
CREATE INDEX "tasks_categoryId_idx" ON "tasks"("categoryId");

-- AddForeignKey
ALTER TABLE "tasks" ADD CONSTRAINT "tasks_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES "task_categories"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "task_categories" ADD CONSTRAINT "task_categories_projectId_fkey" FOREIGN KEY ("projectId") REFERENCES "projects"("id") ON DELETE CASCADE ON UPDATE CASCADE;

