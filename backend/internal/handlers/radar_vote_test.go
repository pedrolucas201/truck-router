package handlers

import (
	"testing"
	"time"
)

// v é um voto de um motorista DIFERENTE a cada chamada. Antes os casos abaixo
// usavam literal posicional sem dono; com a contagem por aparelho, dono vazio
// colapsaria todos em um só e todo caso viraria N=1 — por isso cada voto de
// motorista distinto precisa dizer de qual aparelho veio.
func v(exists bool, kmh int, dono string) voto {
	return voto{Exists: exists, Kmh: kmh, Dono: dono}
}

// A regra que o Pedro escolheu em 17/09/2026, caso por caso. Se algum destes
// quebrar, a maioria para de valer ou passa a valer quando não devia — e o
// efeito é o motorista vendo um limite que ninguém votou.
func TestDecidirVotos(t *testing.T) {
	casos := []struct {
		nome string
		vs   []voto
		quer placar
	}{
		{"sem voto: ninguem manda",
			nil,
			placar{N: 0}},

		// O caso que o Pedro descreveu: Beto 80 x Fernando 90, so os dois.
		{"1x1 abaixo do piso: cada um segue com o seu",
			[]voto{v(true, 80, "a"), v(true, 90, "b")},
			placar{N: 2, Exists: true, Kmh: 0, MandaExists: false, MandaKmh: false}},

		{"1 voto so: nao manda em ninguem",
			[]voto{v(true, 80, "a")},
			placar{N: 1, Exists: true, MandaExists: false, MandaKmh: false}},

		// "se 90 pessoas concordam e 1 discorda, a que discorda aceita a da maioria"
		{"2x1 no piso: maioria manda pra todos",
			[]voto{v(true, 80, "a"), v(true, 80, "b"), v(true, 90, "c")},
			placar{N: 3, Exists: true, Kmh: 80, MandaExists: true, MandaKmh: true}},

		{"empate 2x2 com piso atingido: limite nao muda",
			[]voto{v(true, 80, "a"), v(true, 80, "b"), v(true, 90, "c"), v(true, 90, "d")},
			placar{N: 4, Exists: true, Kmh: 0, MandaExists: true, MandaKmh: false}},

		{"maioria diz que NAO existe",
			[]voto{v(false, 0, "a"), v(false, 0, "b"), v(true, 80, "c")},
			placar{N: 3, Exists: false, Kmh: 0, MandaExists: true, MandaKmh: false}},

		{"empate sobre existir: nao manda",
			[]voto{v(false, 0, "a"), v(true, 80, "b"), v(false, 0, "c"), v(true, 80, "d")},
			placar{N: 4, Exists: true, Kmh: 0, MandaExists: false, MandaKmh: false}},

		// Quem diz "nao existe" nao tem opiniao sobre a placa: se contasse como
		// voto de limite, um "nao existe" derrubaria o limite da maioria.
		{"quem vota nao-existe nao conta no limite",
			[]voto{v(true, 80, "a"), v(true, 80, "b"), v(true, 80, "c"), v(false, 0, "d")},
			placar{N: 4, Exists: true, Kmh: 80, MandaExists: true, MandaKmh: true}},

		// Dois votos de 80 nao atingem o piso de 3 COM numero, entao o limite
		// nao muda pra ninguem: publica 0 (= "nao mexe"), nao o mais votado.
		{"tres que existem mas so dois deram numero: limite nao muda",
			[]voto{v(true, 80, "a"), v(true, 80, "b"), v(true, 0, "c")},
			placar{N: 3, Exists: true, Kmh: 0, MandaExists: true, MandaKmh: false}},

		{"unanime em 3: manda nas duas perguntas",
			[]voto{v(true, 60, "a"), v(true, 60, "b"), v(true, 60, "c")},
			placar{N: 3, Exists: true, Kmh: 60, MandaExists: true, MandaKmh: true}},

		// ⭐ O FURO, fechado. Uid trocando a cada abertura gravava um doc por
		// uid; o mesmo motorista atravessava o piso de 3 sozinho e virava dono
		// do radar pra todo mundo. Agora os tres docs sao UM votante.
		{"tres docs do MESMO aparelho: um votante, nao atinge o piso",
			[]voto{v(true, 80, "mesmo"), v(true, 80, "mesmo"), v(true, 80, "mesmo")},
			placar{N: 1, Exists: true, Kmh: 0, MandaExists: false, MandaKmh: false}},

		// E o contrario tem que seguir funcionando: tres motoristas de verdade
		// mandam. Sem este caso, "consertar" seria so calar a curadoria.
		{"tres aparelhos distintos: a maioria segue mandando",
			[]voto{v(true, 80, "x"), v(true, 80, "y"), v(true, 80, "z")},
			placar{N: 3, Exists: true, Kmh: 80, MandaExists: true, MandaKmh: true}},
	}

	for _, c := range casos {
		got := decidirVotos(c.vs)
		if got != c.quer {
			t.Errorf("%s:\n  got  %+v\n  quer %+v", c.nome, got, c.quer)
		}
	}
}

// Colapsar só pode REDUZIR a contagem. Se algum dia aumentar, o piso deixa de
// proteger e um voto vira maioria.
func TestColapsarPorDono(t *testing.T) {
	velho := time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)
	novo := time.Date(2026, 9, 20, 0, 0, 0, 0, time.UTC)

	t.Run("o mais recente do mesmo aparelho vence", func(t *testing.T) {
		vs := []voto{
			{Exists: true, Kmh: 80, Dono: "a", At: velho},
			{Exists: true, Kmh: 60, Dono: "a", At: novo},
		}
		got := colapsarPorDono(vs)
		if len(got) != 1 {
			t.Fatalf("quer 1 votante, veio %d", len(got))
		}
		if got[0].Kmh != 60 {
			t.Errorf("a opiniao velha venceu: kmh=%d, queria 60", got[0].Kmh)
		}
	})

	t.Run("ordem de leitura nao decide", func(t *testing.T) {
		// Mesma dupla na ordem inversa tem que dar o mesmo resultado: o
		// iterador do Firestore nao promete ordem.
		vs := []voto{
			{Exists: true, Kmh: 60, Dono: "a", At: novo},
			{Exists: true, Kmh: 80, Dono: "a", At: velho},
		}
		got := colapsarPorDono(vs)
		if len(got) != 1 || got[0].Kmh != 60 {
			t.Errorf("resultado dependeu da ordem: %+v", got)
		}
	})

	t.Run("aparelhos distintos nao colapsam", func(t *testing.T) {
		vs := []voto{{Dono: "a"}, {Dono: "b"}, {Dono: "c"}}
		if got := colapsarPorDono(vs); len(got) != 3 {
			t.Errorf("quer 3 votantes, veio %d", len(got))
		}
	})
}

// Sem install válido a contagem cai no uid, que é o comportamento anterior:
// é o que faz o APK em campo continuar funcionando igual.
func TestDono(t *testing.T) {
	const hex32 = "0123456789abcdef0123456789abcdef"
	casos := []struct{ install, uid, quer string }{
		{hex32, "uid1", hex32},
		{"", "uid1", "uid1"},
		{"curto", "uid1", "uid1"},
		{"0123456789ABCDEF0123456789ABCDEF", "uid1", "uid1"}, // maiuscula nao vale
		{hex32 + "x", "uid1", "uid1"},
	}
	for _, c := range casos {
		if got := dono(c.install, c.uid); got != c.quer {
			t.Errorf("dono(%q, %q) = %q, quer %q", c.install, c.uid, got, c.quer)
		}
	}
}

// A chave vem do app pra não divergir na 5ª casa; aqui só o formato é aceito.
func TestRidRe(t *testing.T) {
	ok := []string{"-23.29676_-45.96660", "0.00000_0.00000", "-8.12419_-35.31298"}
	for _, s := range ok {
		if !ridRe.MatchString(s) {
			t.Errorf("rid válido reprovou: %q", s)
		}
	}
	ruim := []string{
		"", "abc", "-23.2967_-45.96660", "-23.29676-45.96660",
		"-23.29676_", "-233.29676_-45.96660", "-23.296765_-45.96660",
		"../outro_doc", "-23.29676_-45.96660__x",
	}
	for _, s := range ruim {
		if ridRe.MatchString(s) {
			t.Errorf("rid inválido passou: %q", s)
		}
	}
}
