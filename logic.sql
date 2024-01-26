--init function: initializes session, games and updates partOf, calls the points-by-difficulty check
CREATE OR REPLACE FUNCTION initialize()
    RETURNS VOID AS $$
DECLARE
    i INT := 0;
BEGIN
    INSERT INTO sessions(maxPinT, active)
    VALUES(5, B'1');

    FOR i IN 0..2 LOOP
            INSERT INTO games(active)
            VALUES(B'1');
            INSERT INTO partOf(sessionId)
            SELECT sessionId
            FROM sessions
            WHERE active = B'1'
              AND NOT EXISTS (
                SELECT sessionId
                FROM partOf
                WHERE sessionId = sessions.sessionID
            );
        END LOOP;

    UPDATE partOf
    SET gameId = g.gameId
    FROM games g
    WHERE partOf.sessionId IN (
        SELECT s.sessionId
        FROM sessions s
        WHERE s.active = B'1'
          AND g.active = B'1'
    );
	PERFORM calculate_points();
END;
$$ LANGUAGE plpgsql;



--points-by-difficulty check, called in initialize()
CREATE OR REPLACE FUNCTION calculate_points()
RETURNS VOID AS $$
BEGIN 
	UPDATE questions q
	SET points = sq.difficulty * 10
	FROM statisticsQuestions sq
	WHERE q.questionId = sq.questionId;
END;
$$ LANGUAGE plpgsql;



--end function, sets sessions, games and teams to passive, calls the statistic update which happens after every session
CREATE OR REPLACE FUNCTION decomp()
RETURNS VOID AS $$
BEGIN
    UPDATE sessions
    SET active = B'0'
    WHERE active = B'1';

    UPDATE games
    SET active = B'0'
    WHERE active = B'1';

    UPDATE teams
    SET active = B'0'
    WHERE active = B'1';

    UPDATE plays
    SET teamId = NULL, gameId = NULL
    WHERE teamId IS NOT NULL;

	PERFORM update_stats();
END;
$$ LANGUAGE plpgsql;



--statistic update, called in decomp()
CREATE OR REPLACE FUNCTION update_stats()
RETURNS VOID AS $$
DECLARE 
BEGIN 
	WITH RankedPlayers AS (
		SELECT
			sp.playerId,
			p.points,
			sp.questionRatio,
			ROW_NUMBER() OVER (ORDER BY p.points DESC, sp.questionRatio DESC, sp.playerId) AS placement
		FROM
			statisticsPlayer sp
		JOIN players p ON sp.playerId = p.playerId
	)
	
	UPDATE statisticsPlayer sp
	SET 
		points = rp.points,
		questionRatio = rp.questionRatio,
		placement = rp.placement
	FROM RankedPlayers rp
	WHERE sp.playerId = rp.playerId;
END;
$$ LANGUAGE plpgsql;



--updates plays for the teamleaders since they are added through the creation of the teams
CREATE OR REPLACE FUNCTION add_team_leader_to_plays()
    RETURNS TRIGGER AS $$
DECLARE
    game_session RECORD;
BEGIN
    UPDATE plays
    SET teamId = NEW.teamId
    WHERE plays.playerId = NEW.teamLeaderId AND plays.gameId IS NULL;

    FOR game_session IN (
        SELECT gameId, sessionId
        FROM partOf
        WHERE gameId IS NOT NULL AND sessionId IS NOT NULL
    ) LOOP
            UPDATE plays
            SET gameId = game_session.gameId
            FROM players
            WHERE teamId = NEW.teamId;

        END LOOP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


--trigger: calls the teamleader-adding function
CREATE TRIGGER tteamleader
    AFTER INSERT ON teams
    FOR EACH ROW
EXECUTE FUNCTION add_team_leader_to_plays();



--adds a question to a game and then diesplays it as a notice
--@Maria: is there a way to make sure the same game is not called constantly? like delivering the gameId as a parameter? because that would work with the nonexistant java file.
--@Maria: possibly assign with order by gesamtantworten asc limit 5 to find the least answered questions
CREATE OR REPLACE FUNCTION start_game()
RETURNS TRIGGER AS $$
DECLARE
    game_id INT;
    firstquestionID INT;
    firstquestionIDname VARCHAR(50);
BEGIN
    SELECT gameId INTO game_id
    FROM games
    WHERE active = B'1'
    LIMIT 1;

    INSERT INTO features(gameId,questionId, qname )
    SELECT game_id, questionId, qname
    FROM questions
    WHERE questionId NOT IN (SELECT questionId FROM features WHERE gameId=game_id)
    ORDER BY RANDOM()
    LIMIT 1
    RETURNING questionId, qname INTO firstquestionID, firstquestionIDname;


    RAISE NOTICE 'Die erste Frage lautet: %', firstquestionIDname;
    RAISE NOTICE 'Antwortmöglichkeiten:';
    RAISE NOTICE '1. %', (SELECT answer1 FROM questions WHERE questionId = firstquestionid);
    RAISE NOTICE '2. %', (SELECT answer2 FROM questions WHERE questionId = firstquestionid);
    RAISE NOTICE '3. %', (SELECT answer3 FROM questions WHERE questionId = firstquestionid);
    RAISE NOTICE '4. %', (SELECT answer4 FROM questions WHERE questionId = firstquestionid);
    PERFORM assign_questions_batch();
END
$$ LANGUAGE plpgsql;



--trigger that starts the game ? for each question.
--@Maria: possibly: you do not need to find the gameId externally, it is saved in the table already. and possibly also modify the function as such, that it doesnt refer to the FIRST question.
--@Maria: also possibly clause: where question is not answered and game is active?
CREATE TRIGGER tfirstquestion
    AFTER INSERT ON features
    FOR EACH ROW
EXECUTE FUNCTION start_game();



--@Maria: do you still need this? all the questions are being called by the above function? cause the trigger adresses every line?
CREATE OR REPLACE FUNCTION assign_next_question()
	RETURNS TRIGGER AS $$
DECLARE
	question_record RECORD;
BEGIN

	SELECT questionId, qname
	INTO question_record
	FROM questions
	WHERE questionId NOT IN (SELECT questionId FROM features WHERE features.gameId = NEW.gameId)
	ORDER BY RANDOM()
	LIMIT 1;


	INSERT INTO features(gameId, questionId, qname)
	VALUES (NEW.gameId, question_record.questionId, question_record.qname);

	RETURN NEW;
END
$$ LANGUAGE plpgsql;



--@Maria: again, do we need this?
CREATE TRIGGER nextquestion
	AFTER INSERT ON features
	FOR EACH ROW
EXECUTE FUNCTION assign_next_question();



--@Maria: once more, do we need this? i dont think so. arent we supposed to do that maually because no java, like with the players?
CREATE OR REPLACE FUNCTION assign_questions_batch()
    RETURNS TRIGGER AS $$
DECLARE
    question_record RECORD;
    question_cursor CURSOR FOR
        SELECT questionId, qname
        FROM questions
        WHERE questionId NOT IN (SELECT questionId FROM features WHERE NEW.gameId = features.gameId)
        ORDER BY RANDOM()
        LIMIT 5;
BEGIN
    OPEN question_cursor;
    FOR question_record IN question_cursor
        LOOP
            INSERT INTO features(gameId, questionId, qname)
            VALUES (NEW.gameId, question_record.questionId, question_record.qname);
        END LOOP;
    CLOSE question_cursor;
    RETURN NEW;
END
$$ LANGUAGE plpgsql;



--@Maria: see corresponding function
CREATE TRIGGER assignquestion
    AFTER INSERT ON features
    FOR EACH ROW
EXECUTE PROCEDURE assign_questions_batch();



--delivers an answer to a question, check, if it is correct and then points. 
--@Val: need to check, if valid. possibly link to the assigning trigger.
CREATE OR REPLACE FUNCTION answer_question(question INT, answer INT, player INT)
RETURNS VOID AS $$
DECLARE
	correct BIT;
	team INT;
	prevPPoints INT;
	prevTpoints INT;
	qPoints INT;
BEGIN
	IF(
		(SELECT rightAnswer
		FROM questions
		WHERE (questionId = question))
		= answer
	)
	THEN
		correct := B'0';
		-- true

		team := (SELECT teamId FROM plays WHERE playerId = player);

		prevPPoints := (SELECT points FROM players WHERE playerId = player);
		prevTPoints := (SELECT points FROM teams WHERE teamId = team);
		qPoints := (SELECT points FROM questions WHERE questionId = question);

		UPDATE players SET points = (prevPPoints + qPoints) WHERE playerId = player;
		UPDATE teams SET points = (prevTPoints + qPoints) WHERE teamId = team;

		UPDATE statisticsPlayer SET questionRatio = (questionRatio + 1) WHERE playerId = player;
	ELSE
		correct := B'1';
		-- false

		UPDATE statisticsPlayer SET questionRatio = (questionRatio - 1) WHERE playerId = player;
	END IF;

	INSERT INTO answered (playerId, questionId, isCorrect, added)
	VALUES (player, question, correct, B'1');
END;
$$ LANGUAGE plpgsql;


-- checks difficulty of questions by calculating it of the given answers. 
-- wrong:difficulty: 0-20%: 1, 30-40%: 2, 50-60%: 3, 70-80%: 4, 90-100%: 5
CREATE OR REPLACE FUNCTION check_difficulty(question_row INT)
RETURNS VOID AS $$
DECLARE
	dif INT;
	righta INT;
	wronga INT;
	question_id INT;
BEGIN
	SELECT questionId INTO question_id
	FROM answered
	WHERE nom = question_row;

	SELECT rightAnswers, wrongAnswers INTO righta, wronga
    FROM statisticsQuestions
    WHERE questionId = question_id;

	IF (righta + wronga != 0)
	THEN
		dif := ((10 - (righta * 10) / (righta + wronga)) / 2);
		IF(dif = 0)
		THEN
			dif := 1;
		END IF;
	ELSE
		dif := 0;
	END IF;


	UPDATE statisticsQuestions
	SET difficulty = dif
	WHERE questionId = question_id;
END;
$$ LANGUAGE plpgsql;


--creates statistics for questions through right and wrong answers. through trigger
CREATE OR REPLACE FUNCTION create_statistic_for_question()
RETURNS TRIGGER AS $$
DECLARE
    question_id INT;
	col INT;
BEGIN
    SELECT questionId INTO question_id
    FROM answered
	ORDER BY nom DESC
    LIMIT 1;

	SELECT nom into col
	FROM answered
	ORDER BY nom DESC
	LIMIT 1;

    IF (SELECT isCorrect FROM answered WHERE nom = col) = B'0'
	THEN
        UPDATE statisticsQuestions
        SET rightAnswers = rightAnswers + 1
        WHERE questionId = question_id;
    ELSE
        UPDATE statisticsQuestions
        SET wrongAnswers = wrongAnswers + 1
        WHERE questionId = question_id;
    END IF;

	UPDATE answered
	SET added = B'0'
	WHERE added = B'1';

	PERFORM check_difficulty(col);

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;



--triggers update of statistics if a question is answered. 
--@Val: also possibly clause if it is in the game. have to check that before inputting in answered.
CREATE TRIGGER tqueststat
AFTER INSERT ON answered
FOR EACH STATEMENT
EXECUTE FUNCTION create_statistic_for_question();