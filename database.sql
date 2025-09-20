-- FINHIGH Financial Management Database Schema
-- Create database
CREATE DATABASE IF NOT EXISTS finhigh_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE finhigh_db;

-- Users table
CREATE TABLE users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    monthly_allowance DECIMAL(10,2) NOT NULL,
    current_balance DECIMAL(10,2) DEFAULT 0.00,
    total_savings DECIMAL(10,2) DEFAULT 0.00,
    total_spent DECIMAL(10,2) DEFAULT 0.00,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_email (email),
    INDEX idx_created_at (created_at)
);

-- Expense categories table
CREATE TABLE expense_categories (
    id INT PRIMARY KEY AUTO_INCREMENT,
    category_name VARCHAR(100) NOT NULL UNIQUE,
    icon_class VARCHAR(100) NOT NULL,
    display_name VARCHAR(150) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert default expense categories
INSERT INTO expense_categories (category_name, icon_class, display_name) VALUES
('food', 'fas fa-utensils', 'Food & Dining'),
('shopping', 'fas fa-shopping-bag', 'Shopping'),
('friends', 'fas fa-users', 'Friends & Social'),
('weekend', 'fas fa-glass-cheers', 'Weekend Outing'),
('social', 'fas fa-hands-helping', 'Social Service');

-- Transactions table
CREATE TABLE transactions (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    transaction_type ENUM('income', 'expense') NOT NULL,
    category VARCHAR(100),
    amount DECIMAL(10,2) NOT NULL,
    description TEXT,
    source VARCHAR(100), -- For income transactions
    transaction_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_id (user_id),
    INDEX idx_transaction_type (transaction_type),
    INDEX idx_category (category),
    INDEX idx_transaction_date (transaction_date)
);

-- User expense summaries table (for quick category totals)
CREATE TABLE user_expense_summaries (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    category VARCHAR(100) NOT NULL,
    total_amount DECIMAL(10,2) DEFAULT 0.00,
    transaction_count INT DEFAULT 0,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE KEY unique_user_category (user_id, category),
    INDEX idx_user_id (user_id),
    INDEX idx_category (category)
);

-- AI Chat messages table
CREATE TABLE chat_messages (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    message_type ENUM('user', 'ai') NOT NULL,
    message_content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_id (user_id),
    INDEX idx_created_at (created_at)
);

-- Financial goals table (for future enhancements)
CREATE TABLE financial_goals (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    goal_name VARCHAR(255) NOT NULL,
    target_amount DECIMAL(10,2) NOT NULL,
    current_amount DECIMAL(10,2) DEFAULT 0.00,
    target_date DATE,
    status ENUM('active', 'completed', 'paused') DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_id (user_id),
    INDEX idx_status (status)
);

-- Reminders table
CREATE TABLE reminders (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    reminder_type VARCHAR(100) NOT NULL,
    message TEXT NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_id (user_id),
    INDEX idx_reminder_type (reminder_type)
);

-- Create stored procedures for common operations

-- Procedure to add a new user
DELIMITER $$
CREATE PROCEDURE AddNewUser(
    IN p_name VARCHAR(255),
    IN p_email VARCHAR(255),
    IN p_allowance DECIMAL(10,2)
)
BEGIN
    DECLARE savings_deduction DECIMAL(10,2) DEFAULT 100.00;
    DECLARE available_balance DECIMAL(10,2);
    
    SET available_balance = p_allowance - savings_deduction;
    
    START TRANSACTION;
    
    INSERT INTO users (name, email, monthly_allowance, current_balance, total_savings)
    VALUES (p_name, p_email, p_allowance, available_balance, savings_deduction);
    
    -- Initialize expense summaries for all categories
    INSERT INTO user_expense_summaries (user_id, category, total_amount)
    SELECT LAST_INSERT_ID(), category_name, 0.00
    FROM expense_categories;
    
    COMMIT;
    
    SELECT LAST_INSERT_ID() as user_id;
END$$
DELIMITER ;

-- Procedure to add expense transaction
DELIMITER $$
CREATE PROCEDURE AddExpenseTransaction(
    IN p_user_id INT,
    IN p_category VARCHAR(100),
    IN p_amount DECIMAL(10,2),
    IN p_description TEXT
)
BEGIN
    START TRANSACTION;
    
    -- Check if user has sufficient balance
    IF (SELECT current_balance FROM users WHERE id = p_user_id) >= p_amount THEN
        -- Insert transaction
        INSERT INTO transactions (user_id, transaction_type, category, amount, description)
        VALUES (p_user_id, 'expense', p_category, p_amount, p_description);
        
        -- Update user balances
        UPDATE users 
        SET current_balance = current_balance - p_amount,
            total_spent = total_spent + p_amount
        WHERE id = p_user_id;
        
        -- Update category summary
        INSERT INTO user_expense_summaries (user_id, category, total_amount, transaction_count)
        VALUES (p_user_id, p_category, p_amount, 1)
        ON DUPLICATE KEY UPDATE
            total_amount = total_amount + p_amount,
            transaction_count = transaction_count + 1;
        
        COMMIT;
        SELECT 'SUCCESS' as status, 'Expense added successfully' as message;
    ELSE
        ROLLBACK;
        SELECT 'ERROR' as status, 'Insufficient balance' as message;
    END IF;
END$$
DELIMITER ;

-- Procedure to add income transaction
DELIMITER $$
CREATE PROCEDURE AddIncomeTransaction(
    IN p_user_id INT,
    IN p_amount DECIMAL(10,2),
    IN p_source VARCHAR(100),
    IN p_description TEXT
)
BEGIN
    DECLARE savings_amount DECIMAL(10,2);
    DECLARE balance_amount DECIMAL(10,2);
    
    -- Split income: 50% savings, 50% balance
    SET savings_amount = p_amount / 2;
    SET balance_amount = p_amount / 2;
    
    START TRANSACTION;
    
    -- Insert transaction
    INSERT INTO transactions (user_id, transaction_type, amount, source, description)
    VALUES (p_user_id, 'income', p_amount, p_source, p_description);
    
    -- Update user balances
    UPDATE users 
    SET current_balance = current_balance + balance_amount,
        total_savings = total_savings + savings_amount
    WHERE id = p_user_id;
    
    COMMIT;
    SELECT 'SUCCESS' as status, 'Income added successfully' as message;
END$$
DELIMITER ;

-- Function to get user dashboard data
DELIMITER $$
CREATE PROCEDURE GetUserDashboard(IN p_user_id INT)
BEGIN
    -- Get user basic info
    SELECT 
        id, name, email, monthly_allowance, current_balance, 
        total_savings, total_spent, notes
    FROM users 
    WHERE id = p_user_id;
    
    -- Get expense summaries
    SELECT 
        ues.category, 
        ues.total_amount, 
        ues.transaction_count,
        ec.icon_class,
        ec.display_name
    FROM user_expense_summaries ues
    JOIN expense_categories ec ON ues.category = ec.category_name
    WHERE ues.user_id = p_user_id
    ORDER BY ues.total_amount DESC;
    
    -- Get recent transactions
    SELECT 
        id, transaction_type, category, amount, description, 
        source, transaction_date
    FROM transactions 
    WHERE user_id = p_user_id 
    ORDER BY transaction_date DESC 
    LIMIT 20;
END$$
DELIMITER ;

-- Create views for commonly used queries

-- View for transaction history with formatted dates
CREATE VIEW transaction_history_view AS
SELECT 
    t.id,
    t.user_id,
    t.transaction_type,
    t.category,
    t.amount,
    t.description,
    t.source,
    t.transaction_date,
    DATE_FORMAT(t.transaction_date, '%d %M %Y at %h:%i %p') as formatted_date,
    u.name as user_name
FROM transactions t
JOIN users u ON t.user_id = u.id;

-- View for spending analysis
CREATE VIEW spending_analysis_view AS
SELECT 
    u.id as user_id,
    u.name,
    u.monthly_allowance,
    u.current_balance,
    u.total_spent,
    u.total_savings,
    ROUND((u.total_spent / u.monthly_allowance) * 100, 2) as spent_percentage,
    CASE 
        WHEN (u.total_spent / u.monthly_allowance) * 100 < 50 THEN 'GOOD'
        WHEN (u.total_spent / u.monthly_allowance) * 100 < 75 THEN 'MODERATE'
        ELSE 'HIGH'
    END as spending_status
FROM users u;

-- Insert sample data for testing (optional)
-- INSERT INTO users (name, email, monthly_allowance, current_balance, total_savings, total_spent) 
-- VALUES ('John Doe', 'john@example.com', 5000.00, 4400.00, 100.00, 500.00);

-- Create indexes for better performance
CREATE INDEX idx_users_updated_at ON users(updated_at);
CREATE INDEX idx_transactions_user_date ON transactions(user_id, transaction_date);
CREATE INDEX idx_expense_summaries_user_category ON user_expense_summaries(user_id, category);

-- Grant privileges (adjust as needed for your setup)
-- CREATE USER 'finhigh_user'@'localhost' IDENTIFIED BY 'your_secure_password';
-- GRANT SELECT, INSERT, UPDATE, DELETE ON finhigh_db.* TO 'finhigh_user'@'localhost';
-- FLUSH PRIVILEGES;
