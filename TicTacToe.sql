/* Welcome to TicTacToe in T-SQL ! */




/* Create the database */
IF DB_ID('TicTacToe') IS NULL
    CREATE DATABASE TicTacToe
GO




/* Use the database */
USE TicTacToe




/* Create the types */
CREATE TYPE BOARD_POSITION AS TABLE (
    Horizontal int  NOT NULL,
    Vertical   int  NOT NULL,
    Player     char NOT NULL,

    CHECK (Horizontal IN (1,2,3)),
    CHECK (Vertical IN (1,2,3)),
    CHECK (Player in ('X','O')),
    UNIQUE (Horizontal, Vertical)
)
CREATE TYPE DISPLAY_BOARD AS TABLE (
    Vertical varchar(2) NOT NULL,
    H1       char       NOT NULL,
    H2       char       NOT NULL,
    H3       char       NOT NULL,

    CHECK (Vertical IN ('V1', 'V2', 'V3')),
    CHECK (H1 IN ('X', 'O', ' ')),
    CHECK (H2 IN ('X', 'O', ' ')),
    CHECK (H3 IN ('X', 'O', ' '))
)




/* Create the tables */
-- contains the game mode (easy, hard, free, ...)
IF OBJECT_ID('GENERAL_INFORMATION', 'U') IS NULL
    CREATE TABLE GENERAL_INFORMATION (
        Info varchar(20) NOT NULL,
    )
-- I can't create a table of type 'BOARD_POSITION' unfortunately
IF OBJECT_ID('GAME_BOARD', 'U') IS NULL
    CREATE TABLE GAME_BOARD (
        Horizontal int  NOT NULL,
        Vertical   int  NOT NULL,
        Player     char NOT NULL,

        CHECK (Horizontal IN (1,2,3)),
        CHECK (Vertical IN (1,2,3)),
        CHECK (Player in ('X','O')),
        UNIQUE (Horizontal, Vertical)
    )
GO




/* Functions */
-- returns 1 if this is the easy mode
CREATE FUNCTION IS_EASY_MODE() RETURNS INT
BEGIN
    IF 'easy' IN ( SELECT Info FROM GENERAL_INFORMATION ) RETURN 1 RETURN 0
END
GO
-- returns 1 if this is the hard mode
CREATE FUNCTION IS_HARD_MODE() RETURNS INT
BEGIN
    IF 'hard' IN ( SELECT * FROM GENERAL_INFORMATION ) RETURN 1 RETURN 0
END
GO
-- returns 1 if this is the hard mode
CREATE FUNCTION IS_INVINCIBLE_MODE() RETURNS INT
BEGIN
    IF 'invincible' IN ( SELECT * FROM GENERAL_INFORMATION ) RETURN 1 RETURN 0
END
GO
-- returns 1 if the position is already taken, 0 otherwise
CREATE FUNCTION IS_OCCUPIED(
    @Horizontal int,
    @Vertical int,
    @Board BOARD_POSITION READONLY
) RETURNS INT
BEGIN
    DECLARE @Player CHAR
    SET @Player = (
        SELECT Player FROM GAME_BOARD
        WHERE Horizontal = @Horizontal AND Vertical = @Vertical
    )

    IF @Player IS NOT NULL RETURN 1 RETURN 0
END
GO
-- returns the player on the given position (' ' if no player)
CREATE FUNCTION GET_PLAYER(
    @Horizontal int,
    @Vertical int,
    @Board BOARD_POSITION READONLY
) RETURNS CHAR
BEGIN
    DECLARE @Player CHAR
    SET @Player = (
        SELECT Player FROM @Board
        WHERE Horizontal = @Horizontal AND Vertical = @Vertical
    )

    IF @Player IS NULL RETURN ' ' RETURN @Player
END
GO
-- returns 'X' or 'O' depending on who plays next turn
CREATE FUNCTION GET_TURN(@Board BOARD_POSITION READONLY) RETURNS CHAR
BEGIN
    DECLARE @Turn INT
    SET @Turn = ( SELECT COUNT(*) FROM @Board )

    IF @Turn % 2 = 0 RETURN 'X' RETURN 'O'
END
GO
-- returns NULL if no winner
CREATE FUNCTION GET_WINNER(@Board BOARD_POSITION READONLY) RETURNS CHAR
BEGIN
    DECLARE @Winner CHAR

    -- Horizontal
    SET @Winner = (
        SELECT Player FROM @Board
        GROUP BY Horizontal, Player HAVING COUNT(Player) = 3
    )
    IF @Winner IS NOT NULL RETURN @Winner

    -- Vertical
    SET @Winner = (
        SELECT Player FROM @Board
        GROUP BY Vertical, Player HAVING COUNT(Player) = 3
    )
    IF @Winner IS NOT NULL RETURN @Winner

    -- south-west to north-east diagonal
    SET @Winner = (
        SELECT Player FROM @Board
        WHERE Horizontal = Vertical
        GROUP BY Player
        HAVING COUNT(*) = 3
    )
    IF @Winner IS NOT NULL RETURN @Winner

    -- north-west to south-east diagonal
    SET @Winner = (
        SELECT Player FROM @Board
        WHERE Horizontal + Vertical = 4
        GROUP BY Player
        HAVING COUNT(*) = 3
    )
    RETURN @Winner -- may be NULL
END
GO
-- returns 1 if the game is over, 0 otherwise
CREATE FUNCTION IS_GAME_OVER(@Board BOARD_POSITION READONLY) RETURNS INT
BEGIN
    IF (SELECT COUNT(*) FROM @Board) = 9 OR dbo.GET_WINNER(@Board) IS NOT NULL
        RETURN 1
    RETURN 0
END
GO




/* easy ai that plays randomly */
-- this view is necessary because you cannot use the :
-- "side-effecting operator 'rand' within a function"
CREATE VIEW GET_RAND_VAL
AS
    SELECT RAND() AS Value
GO
-- returns a random number between 1 and 3
CREATE FUNCTION RANDOM_1_3() RETURNS INT
BEGIN
    RETURN CEILING((SELECT Value FROM GET_RAND_VAL) * 3)
END
GO
-- returns a position
CREATE PROCEDURE POSITION_EASY_AI
    @OutHorizontal int OUTPUT,
    @OutVertical int OUTPUT
AS
BEGIN
    DECLARE @GameState AS BOARD_POSITION
    INSERT INTO @GameState SELECT * FROM GAME_BOARD

    SET @OutHorizontal = dbo.RANDOM_1_3()
    SET @OutVertical = dbo.RANDOM_1_3()

    WHILE dbo.IS_OCCUPIED(@OutHorizontal, @OutVertical, @GameState) = 1
    BEGIN
        SET @OutHorizontal = dbo.RANDOM_1_3()
        SET @OutVertical = dbo.RANDOM_1_3()
    END
END
GO




/* hard ai */
-- returns a position
CREATE PROCEDURE POSITION_HARD_AI
    @OutHorizontal int OUTPUT,
    @OutVertical int OUTPUT
AS
BEGIN
    CREATE TABLE #LocalTempBoard ( Num int )
    INSERT INTO #LocalTempBoard VALUES (1),(2),(3)

    -- find every free position of the board
    DECLARE @EveryFreePosition AS BOARD_POSITION
    INSERT INTO @EveryFreePosition
        SELECT
            H.Num AS Horizontal,
            V.Num AS Vertical,
            'O' AS Player
        FROM #LocalTempBoard H CROSS JOIN #LocalTempBoard V
        EXCEPT SELECT Horizontal, Vertical, 'O' FROM GAME_BOARD

    -- cursor on free positions
    DECLARE position_cursor SCROLL CURSOR
    FOR SELECT Horizontal, Vertical FROM @EveryFreePosition
    OPEN position_cursor
    FETCH FIRST FROM position_cursor INTO @OutHorizontal, @OutVertical

    -- 1. Take spot if going to win
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @NewBoard AS BOARD_POSITION
        INSERT INTO @NewBoard SELECT * FROM GAME_BOARD UNION SELECT @OutHorizontal, @OutVertical, 'O'

        IF dbo.GET_WINNER(@NewBoard) = 'O' BEGIN
            SET @OutHorizontal = @OutHorizontal
            SET @OutVertical = @OutVertical
            RETURN
        END

        DELETE FROM @NewBoard
        FETCH NEXT FROM position_cursor INTO @OutHorizontal, @OutVertical
    END

    -- 2. Take spot if going to lose
    FETCH FIRST FROM position_cursor INTO @OutHorizontal, @OutVertical -- reset the cursor
    WHILE @@FETCH_STATUS = 0
    BEGIN
        INSERT INTO @NewBoard SELECT * FROM GAME_BOARD UNION SELECT @OutHorizontal, @OutVertical, 'X'

        IF dbo.GET_WINNER(@NewBoard) = 'X' BEGIN
            SET @OutHorizontal = @OutHorizontal
            SET @OutVertical = @OutVertical
            RETURN
        END

        DELETE FROM @NewBoard
        FETCH NEXT FROM position_cursor INTO @OutHorizontal, @OutVertical
    END

    CLOSE position_cursor
    DEALLOCATE position_cursor

    -- 3. Take center
    SET @OutHorizontal = 2
    SET @OutVertical = 2
    IF EXISTS (SELECT Horizontal, Vertical FROM @EveryFreePosition
        WHERE Horizontal = 2 AND Vertical = 2)
        RETURN

    -- 4. Take non-corner non-center
    SELECT
        @OutHorizontal = FIRST_VALUE(Horizontal) OVER (PARTITION BY Vertical ORDER BY Horizontal),
        @OutVertical = FIRST_VALUE(Vertical) OVER (PARTITION BY Vertical ORDER BY Horizontal)
    FROM @EveryFreePosition
    WHERE Horizontal + Vertical IN (3, 5)   -- (1,2), (2,1), (3,2), (2,3)
    IF @OutHorizontal IS NOT NULL RETURN

    -- 5. Take corner
    SELECT
        @OutHorizontal = FIRST_VALUE(Horizontal) OVER (PARTITION BY Vertical ORDER BY Horizontal),
        @OutVertical = FIRST_VALUE(Vertical) OVER (PARTITION BY Vertical ORDER BY Horizontal)
    FROM @EveryFreePosition
    WHERE Horizontal + Vertical IN (2, 4, 6)    -- (1,1), (1,3), (3,1), (3,3)
    IF @OutHorizontal IS NOT NULL RETURN
END
GO




/* invincible ai */
-- returns a position
CREATE PROCEDURE POSITION_INVINCIBLE_AI
    @OutHorizontal int OUTPUT,
    @OutVertical int OUTPUT
AS
BEGIN
    CREATE TABLE #LocalTempBoard ( Num int )
    INSERT INTO #LocalTempBoard VALUES (1),(2),(3)

    -- find every free position of the board
    DECLARE @EveryFreePosition AS BOARD_POSITION
    INSERT INTO @EveryFreePosition
        SELECT
            H.Num AS Horizontal,
            V.Num AS Vertical,
            'O' AS Player
        FROM #LocalTempBoard H CROSS JOIN #LocalTempBoard V
        EXCEPT SELECT Horizontal, Vertical, 'O' FROM GAME_BOARD

    -- cursor on free positions
    DECLARE position_cursor SCROLL CURSOR
    FOR SELECT Horizontal, Vertical FROM @EveryFreePosition
    OPEN position_cursor
    FETCH FIRST FROM position_cursor INTO @OutHorizontal, @OutVertical

    -- 1. Take spot if going to win
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @NewBoard AS BOARD_POSITION
        INSERT INTO @NewBoard SELECT * FROM GAME_BOARD UNION SELECT @OutHorizontal, @OutVertical, 'O'

        IF dbo.GET_WINNER(@NewBoard) = 'O' BEGIN
            SET @OutHorizontal = @OutHorizontal
            SET @OutVertical = @OutVertical
            RETURN
        END

        DELETE FROM @NewBoard
        FETCH NEXT FROM position_cursor INTO @OutHorizontal, @OutVertical
    END

    -- 2. Take spot if going to lose
    FETCH FIRST FROM position_cursor INTO @OutHorizontal, @OutVertical -- reset the cursor
    WHILE @@FETCH_STATUS = 0
    BEGIN
        INSERT INTO @NewBoard SELECT * FROM GAME_BOARD UNION SELECT @OutHorizontal, @OutVertical, 'X'

        IF dbo.GET_WINNER(@NewBoard) = 'X' BEGIN
            SET @OutHorizontal = @OutHorizontal
            SET @OutVertical = @OutVertical
            RETURN
        END

        DELETE FROM @NewBoard
        FETCH NEXT FROM position_cursor INTO @OutHorizontal, @OutVertical
    END

    CLOSE position_cursor
    DEALLOCATE position_cursor

    -- 3. Take center
    SET @OutHorizontal = 2
    SET @OutVertical = 2
    IF EXISTS (SELECT Horizontal, Vertical FROM @EveryFreePosition
        WHERE Horizontal = 2 AND Vertical = 2)
        RETURN

    -- 4. Take corner
    SELECT
        @OutHorizontal = FIRST_VALUE(Horizontal) OVER (PARTITION BY Vertical ORDER BY Horizontal),
        @OutVertical = FIRST_VALUE(Vertical) OVER (PARTITION BY Vertical ORDER BY Horizontal)
    FROM @EveryFreePosition
    WHERE Horizontal + Vertical IN (2, 4, 6)    -- (1,1), (1,3), (3,1), (3,3)
    IF @OutHorizontal IS NOT NULL RETURN

    -- 5. Take non-corner non-center
    SELECT
        @OutHorizontal = FIRST_VALUE(Horizontal) OVER (PARTITION BY Vertical ORDER BY Horizontal),
        @OutVertical = FIRST_VALUE(Vertical) OVER (PARTITION BY Vertical ORDER BY Horizontal)
    FROM @EveryFreePosition
    WHERE Horizontal + Vertical IN (3, 5)   -- (1,2), (2,1), (3,2), (2,3)
    IF @OutHorizontal IS NOT NULL RETURN
END
GO




/* Procedures to display something */
-- show the board to the user
CREATE PROCEDURE ShowBoard
AS
    DECLARE @GameState AS BOARD_POSITION
    INSERT INTO @GameState SELECT * FROM GAME_BOARD

    DECLARE @DisplayBoard DISPLAY_BOARD
    DECLARE @v int
    SET @v = 1

    -- insert values into the display table with a loop
    WHILE @v <= 3
    BEGIN
        INSERT INTO @DisplayBoard VALUES (
            N'V' + CAST(@v AS CHAR),
            dbo.GET_PLAYER(1, @v, @GameState),
            dbo.GET_PLAYER(2, @v, @GameState),
            dbo.GET_PLAYER(3, @v, @GameState)
        )

        SET @v = @v + 1
    END

    SELECT * FROM @DisplayBoard
GO
-- prints the player who plays next
CREATE PROCEDURE WhoPlaysNext
AS
    DECLARE @GameState AS BOARD_POSITION
    INSERT INTO @GameState SELECT * FROM GAME_BOARD

    PRINT dbo.GET_TURN(@GameState)
GO
-- prints the game mode
CREATE PROCEDURE ShowMode
AS
BEGIN
    DECLARE @Mode varchar(20)
    SET @Mode = (
        SELECT Info FROM GENERAL_INFORMATION
        WHERE Info IN ('free', 'easy', 'hard', 'invincible')
    )

    IF @Mode IS NULL SET @Mode = 'free'

    PRINT N'Game Mode : ' + @Mode
    SELECT * FROM GENERAL_INFORMATION
END
GO
-- prints the user who won or 'It s a draw'
CREATE PROCEDURE CONGRATULATE_WINNER
AS
BEGIN
    DECLARE @GameState AS BOARD_POSITION
    INSERT INTO @GameState SELECT * FROM GAME_BOARD

    DECLARE @winner CHAR
    SET @Winner = dbo.GET_WINNER(@GameState)

    IF @Winner IS NOT NULL
    BEGIN
        PRINT N'----------------------------------'
        PRINT N'| Player ' + @Winner + N' has won the game ! |'
        PRINT N'----------------------------------'
    END ELSE BEGIN
        PRINT N'---------------'
        PRINT N'| It s a draw. |'
        PRINT N'---------------'
    END

    EXEC ShowBoard
END
GO




/* Change the game state */
-- clear the board
CREATE PROCEDURE ResetGame
AS
    DELETE FROM GAME_BOARD
    PRINT N'Game reset'
GO
-- change the game mode
CREATE PROCEDURE ChangeMode(@Mode varchar(20))
AS
    TRUNCATE TABLE GENERAL_INFORMATION

    IF @Mode NOT IN ('free', 'easy', 'hard', 'invincible') BEGIN
        PRINT N'Error : ' + @Mode + ', not implemented.'
        RETURN
    END

    INSERT INTO GENERAL_INFORMATION VALUES (@Mode)
    EXEC ResetGame
GO
-- add the given position to the board (if legal) and make the AI play
CREATE PROCEDURE Play
    @Horizontal int,
    @Vertical int
AS
    DECLARE @GameState AS BOARD_POSITION
    INSERT INTO @GameState SELECT * FROM GAME_BOARD

    -- check if the game is over
    IF dbo.IS_GAME_OVER(@GameState) = 1 BEGIN
        EXEC CONGRATULATE_WINNER
        RETURN
    END

    -- the player cant play on an occupied position
    IF dbo.IS_OCCUPIED(@Horizontal, @Vertical, @GameState) = 1 BEGIN
        PRINT N'Position already occupied, choose another position'
        EXEC ShowBoard
        RETURN
    END

    -- find which player has made the move, add it to the board
    DECLARE @Player CHAR
    SET @Player = dbo.GET_TURN(@GameState)
    INSERT INTO GAME_BOARD VALUES (@Horizontal, @Vertical, @Player)

    -- check if the game is over
    DELETE FROM @GameState
    INSERT INTO @GameState SELECT * FROM GAME_BOARD
    IF dbo.IS_GAME_OVER(@GameState) = 1 BEGIN
        EXEC CONGRATULATE_WINNER
        RETURN
    END

    -- get a position from the easy ai
    IF dbo.IS_EASY_MODE() = 1 BEGIN
        EXEC POSITION_EASY_AI
            @OutHorizontal = @Horizontal OUTPUT,
            @OutVertical = @Vertical OUTPUT
        INSERT INTO GAME_BOARD VALUES (@Horizontal, @Vertical, 'O')
    END

    -- get a position from the hard ai
    IF dbo.IS_HARD_MODE() = 1 BEGIN
        EXEC POSITION_HARD_AI
            @OutHorizontal = @Horizontal OUTPUT,
            @OutVertical = @Vertical OUTPUT
        INSERT INTO GAME_BOARD VALUES (@Horizontal, @Vertical, 'O')
    END

    --

    -- check if the game is over
    DELETE FROM @GameState
    INSERT INTO @GameState SELECT * FROM GAME_BOARD
    IF dbo.IS_GAME_OVER(@GameState) = 1 BEGIN
        EXEC CONGRATULATE_WINNER
        RETURN
    END

    -- print the table
    EXEC ShowBoard
GO




/* How to play */


PRINT N'-----------------------------'
PRINT N'-- To know who plays next : EXEC WhoPlaysNext;'
PRINT N'-- To see the board : EXEC ShowBoard;'
PRINT N'-- To see the mode : EXEC ShowMode;'
PRINT N'-- Start a new game : EXEC ResetGame;'
PRINT N'-- To play : EXEC Play @Horizontal = ..., @Vertical = ...;'
PRINT N'-- Example : EXEC Play @Horizontal = 1, @Vertical = 1;'
PRINT N'-- Change mode : EXEC ChangeMode @Mode = ...;'
PRINT N'-- -- -- easy (=> AI plays randomly)'
PRINT N'-- -- -- hard (=> smart AI)'
PRINT N'-- -- -- invincible (=> unbeatable AI)'
PRINT N'-- -- -- free (=> for 2 players, default)'
PRINT N'-----------------------------'




/* Show the board */


EXEC ShowBoard




